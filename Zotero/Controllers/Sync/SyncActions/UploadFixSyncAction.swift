//
//  UploadFixSyncAction.swift
//  Zotero
//
//  Created by Michal Rentka on 06.06.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import Alamofire
import CocoaLumberjackSwift
import RxSwift

class UploadFixSyncAction: SyncAction {
    typealias Result = ()

    enum Error: Swift.Error {
        case attachmentMissingRemotely
        case fileNotDownloaded
        case itemNotAttachment
        case incorrectAttachmentType(Attachment.Kind)
        case incorrectLinkType(Attachment.FileLinkType)
        case expired
    }

    let key: String
    let libraryId: LibraryIdentifier
    let userId: Int
    unowned let attachmentDownloader: AttachmentDownloader
    unowned let fileStorage: FileStorage
    unowned let dbStorage: DbStorage
    let queue: DispatchQueue
    let scheduler: SchedulerType
    private let downloadDisposeBag: DisposeBag

    private var finishDownload: ((Swift.Result<(), Swift.Error>) -> Void)?

    init(key: String, libraryId: LibraryIdentifier, userId: Int, attachmentDownloader: AttachmentDownloader, fileStorage: FileStorage, dbStorage: DbStorage, queue: DispatchQueue, scheduler: SchedulerType) {
        self.key = key
        self.libraryId = libraryId
        self.userId = userId
        self.attachmentDownloader = attachmentDownloader
        self.fileStorage = fileStorage
        self.dbStorage = dbStorage
        self.queue = queue
        self.scheduler = scheduler
        self.downloadDisposeBag = DisposeBag()
    }

    var result: Single<()> {
        DDLogInfo("UploadFixSyncAction: fix upload for \(self.key); \(self.libraryId)")

        self.attachmentDownloader
            .observable
            .observe(on: self.scheduler)
            .subscribe(with: self, onNext: { `self`, update in
                guard update.key == self.key && update.libraryId == self.libraryId else { return }

                switch update.kind {
                case .failed(let error):
                    self.finishDownload?(.failure(error))
                    self.finishDownload = nil

                case .ready:
                    self.finishDownload?(.success(()))
                    self.finishDownload = nil
                case .progress, .cancelled: break
                }
            })
            .disposed(by: self.downloadDisposeBag)

        return self.fetchAndValidateAttachment()
                   .subscribe(on: self.scheduler)
                   .flatMap({ attachment -> Single<Attachment> in
                       return self.download(attachment: attachment).flatMap({ Single.just(attachment) })
                   })
                   .flatMap({ attachment in
                       return self.markAsUploaded(attachment: attachment)
                   })
    }

    private func markAsUploaded(attachment: Attachment) -> Single<()> {
        return Single.create { [weak self] subscriber in
            guard let self else {
                subscriber(.failure(Error.expired))
                return Disposables.create()
            }

            do {
                // Mark object as uploaded, since backend already has the file and we just downloaded to match the file locally
                let markAsUploaded = MarkAttachmentUploadedDbRequest(libraryId: self.libraryId, key: self.key, version: nil)
                // Mark for resync so that local object matches remote object in version and md5
                let markForResync = MarkForResyncDbAction<RItem>(libraryId: self.libraryId, keys: [self.key])
                try self.dbStorage.perform(writeRequests: [markAsUploaded, markForResync], on: self.queue)
                subscriber(.success(()))
            } catch let error {
                subscriber(.failure(error))
            }

            return Disposables.create()
        }
    }

    private func download(attachment: Attachment) -> Single<()> {
        return Single.create { [weak self] subscriber in
            guard let self else {
                subscriber(.failure(Error.expired))
                return Disposables.create()
            }

            self.finishDownload = subscriber
            self.attachmentDownloader.downloadIfNeeded(attachment: attachment, parentKey: nil)
            return Disposables.create()
        }
    }

    private func fetchAndValidateAttachment() -> Single<Attachment> {
        return Single.create { [weak self] subscriber in
            guard let self else {
                subscriber(.failure(Error.expired))
                return Disposables.create()
            }

            do {
                let item = try self.dbStorage.perform(request: ReadItemDbRequest(libraryId: self.libraryId, key: self.key), on: self.queue)

                guard item.rawType == ItemTypes.attachment, let attachment = AttachmentCreator.attachment(for: item, options: .light, fileStorage: self.fileStorage, urlDetector: nil) else {
                    DDLogError("UploadFixSyncAction: item not attachment - \(item.rawType)")
                    subscriber(.failure(Error.itemNotAttachment))
                    return Disposables.create()
                }

                switch attachment.type {
                case .url:
                    DDLogError("UploadFixSyncAction: incorrect item type - \(attachment.type)")
                    subscriber(.failure(Error.incorrectAttachmentType(attachment.type)))

                case .file(let filename, let contentType, let location, let linkType):
                    switch linkType {
                    case .embeddedImage, .linkedFile:
                        DDLogError("UploadFixSyncAction: incorrect link type - \(linkType)")
                        subscriber(.failure(Error.incorrectLinkType(linkType)))

                    case .importedFile, .importedUrl:
                        switch location {
                        case .remoteMissing:
                            DDLogError("UploadFixSyncAction: attachment missing remotely")
                            subscriber(.failure(Error.attachmentMissingRemotely))
                            return Disposables.create()

                        case .local, .localAndChangedRemotely, .remote: break
                        }

                        // Create new attachment model with updated location so that `AttachmentDownloader` doesn't ignore it
                        let newAttachment = Attachment(type: .file(filename: filename, contentType: contentType, location: .remote, linkType: linkType),
                                                       title: attachment.title, key: attachment.key, libraryId: attachment.libraryId)
                        subscriber(.success(newAttachment))
                    }
                }
            } catch let error {
                subscriber(.failure(error))
            }

            return Disposables.create()
        }
    }
}
