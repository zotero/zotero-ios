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

struct UploadFixSyncAction: SyncAction {
    typealias Result = ()

    let key: String
    let libraryId: LibraryIdentifier
    let userId: Int

    unowned let attachmentDownloader: AttachmentDownloader
    unowned let fileStorage: FileStorage
    unowned let dbStorage: DbStorage
    let queue: DispatchQueue
    let scheduler: SchedulerType
    private let downloadDisposeBag: DisposeBag

    var result: Single<()> {
        DDLogInfo("UploadFixSyncAction: fix upload for \(self.key); \(self.libraryId)")

        self.attachmentDownloader.observable.observe(on: self.scheduler).subscribe(with: self, onNext: { `self`, update in

        })

        return self.fetchAndValidateAttachment()
                   .subscribe(on: self.scheduler)
                   .flatMap({ attachment in
                       return self.download(attachment: attachment)
                   })
    }

    private func markAsUploaded(attachment: Attachment) -> Single<()> {

    }

    private func download(attachment: Attachment) -> Single<()> {
        return Single.create { subscriber in
            self.attachmentDownloader.downloadIfNeeded(attachment: <#T##Attachment#>, parentKey: <#T##String?#>)
        }
    }

    private func fetchAndValidateAttachment() -> Single<Attachment> {
        return Single.create { subscriber in
            do {
                let item = try self.dbStorage.perform(request: ReadItemDbRequest(libraryId: self.libraryId, key: self.key), on: self.queue)

                guard item.rawType == ItemTypes.attachment, let attachment = AttachmentCreator.attachment(for: item, options: .light, fileStorage: self.fileStorage, urlDetector: nil) else {
                    DDLogError("UploadFixSyncAction: item not attachment")
                    subscriber(.failure(SyncError.Fatal.preconditionErrorCantBeResolved(data: SyncError.ErrorData(itemKeys: [self.key], libraryId: self.libraryId))))
                    return Disposables.create()
                }

                switch attachment.type {
                case .url:
                    DDLogError("UploadFixSyncAction: incorrect item type - \(attachment.type)")
                    subscriber(.failure(SyncError.Fatal.preconditionErrorCantBeResolved(data: SyncError.ErrorData(itemKeys: [self.key], libraryId: self.libraryId))))

                case .file(let filename, let contentType, let location, let linkType):
                    switch linkType {
                    case .embeddedImage, .linkedFile:
                        DDLogError("UploadFixSyncAction: incorrect link type - \(linkType)")
                        subscriber(.failure(SyncError.Fatal.preconditionErrorCantBeResolved(data: SyncError.ErrorData(itemKeys: [self.key], libraryId: self.libraryId))))

                    case .importedFile, .importedUrl:
                        switch location {
                        case .remoteMissing:
                            DDLogError("UploadFixSyncAction: attachment missing remotely")
                            subscriber(.failure(SyncError.Fatal.preconditionErrorCantBeResolved(data: SyncError.ErrorData(itemKeys: [self.key], libraryId: self.libraryId))))
                            return Disposables.create()

                        case .local, .localAndChangedRemotely:
                            // Remove local file if available
                            let file = Files.attachmentFile(in: self.libraryId, key: self.key, filename: filename, contentType: contentType)
                            try? self.fileStorage.remove(file)

                        case .remote: break
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
