//
//  AttachmentDownloader.swift
//  Zotero
//
//  Created by Michal Rentka on 11/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import Alamofire
import CocoaLumberjackSwift
import RxSwift
import ZIPFoundation

final class AttachmentDownloader {
    enum Error: Swift.Error {
        case incompatibleAttachment
        case zipDidntContainRequestedFile
    }

    struct Update {
        enum Kind {
            case progress(CGFloat)
            case ready
            case failed(Swift.Error)
            case cancelled
        }

        let key: String
        let parentKey: String?
        let libraryId: LibraryIdentifier
        let kind: Kind
        
        init(key: String, parentKey: String?, libraryId: LibraryIdentifier, kind: Kind) {
            self.key = key
            self.parentKey = parentKey
            self.libraryId = libraryId
            self.kind = kind
        }
        
        fileprivate init(download: Download, parentKey: String?, kind: Kind) {
            self.key = download.key
            self.parentKey = parentKey
            self.libraryId = download.libraryId
            self.kind = kind
        }
    }

    struct Download: Hashable {
        let key: String
        let libraryId: LibraryIdentifier
    }

    private let userId: Int
    private unowned let apiClient: ApiClient
    private unowned let fileStorage: FileStorage
    private unowned let dbStorage: DbStorage
    private unowned let webDavController: WebDavController
    private let queue: DispatchQueue
    private let operationQueue: OperationQueue
    private let disposeBag: DisposeBag
    let observable: PublishSubject<Update>

    private var operations: [Download: AttachmentDownloadOperation]
    private var progressObservers: [Download: NSKeyValueObservation]
    private var errors: [Download: Swift.Error]

    init(userId: Int, apiClient: ApiClient, fileStorage: FileStorage, dbStorage: DbStorage, webDavController: WebDavController) {
        let queue = DispatchQueue(label: "org.zotero.AttachmentDownloader.ProcessingQueue", qos: .userInteractive, attributes: .concurrent)
        let operationQueue = OperationQueue()
        operationQueue.maxConcurrentOperationCount = 2
        operationQueue.qualityOfService = .userInitiated
        operationQueue.underlyingQueue = queue

        self.userId = userId
        self.apiClient = apiClient
        self.fileStorage = fileStorage
        self.dbStorage = dbStorage
        self.webDavController = webDavController
        self.operations = [:]
        self.progressObservers = [:]
        self.queue = queue
        self.operationQueue = operationQueue
        self.errors = [:]
        self.observable = PublishSubject()
        self.disposeBag = DisposeBag()
    }

    // MARK: - Actions

    func downloadIfNeeded(attachment: Attachment, parentKey: String?) {
        inMainThread { [weak self] in
            self?._downloadIfNeeded(attachment: attachment, parentKey: parentKey)
        }
    }

    private func _downloadIfNeeded(attachment: Attachment, parentKey: String?) {
        switch attachment.type {
        case .url:
            self.observable.on(.next(Update(key: attachment.key, parentKey: parentKey, libraryId: attachment.libraryId, kind: .ready)))
        case .file(let filename, let contentType, let location, let linkType):
            switch linkType {
            case .linkedFile, .embeddedImage:
                self.finish(download: Download(key: attachment.key, libraryId: attachment.libraryId), parentKey: parentKey, result: .failure(Error.incompatibleAttachment), hasLocalCopy: false)
            case .importedFile, .importedUrl:
                switch location {
                case .local:
                    self.observable.on(.next(Update(key: attachment.key, parentKey: parentKey, libraryId: attachment.libraryId, kind: .ready)))
                case .remote, .remoteMissing:
                    let file = Files.attachmentFile(in: attachment.libraryId, key: attachment.key, filename: filename, contentType: contentType)
                    self.download(file: file, key: attachment.key, parentKey: parentKey, libraryId: attachment.libraryId, hasLocalCopy: false)
                case .localAndChangedRemotely:
                    let file = Files.attachmentFile(in: attachment.libraryId, key: attachment.key, filename: filename, contentType: contentType)
                    self.download(file: file, key: attachment.key, parentKey: parentKey, libraryId: attachment.libraryId, hasLocalCopy: true)
                }
            }
        }
    }

    func cancel(key: String, libraryId: LibraryIdentifier) {
        let download = Download(key: key, libraryId: libraryId)
        self.progressObservers[download] = nil

        if let operation = self.operations[download] {
            operation.cancel()
            return
        }
    }

    func data(for key: String, libraryId: LibraryIdentifier) -> (progress: CGFloat?, error: Swift.Error?) {
        let download = Download(key: key, libraryId: libraryId)
        let progress = (self.operations[download]?.progress.fractionCompleted).flatMap({ CGFloat($0) })
        return (progress, self.errors[download])
    }

    // MARK: - Helpers

    private func download(file: File, key: String, parentKey: String?, libraryId: LibraryIdentifier, hasLocalCopy: Bool) {
        let download = Download(key: key, libraryId: libraryId)

        guard self.operations[download] == nil else { return }

        let progress = Progress(totalUnitCount: 100)
        let observer = progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            self?.observable.on(.next(Update(download: download, parentKey: parentKey, kind: .progress(CGFloat(progress.fractionCompleted)))))
        }
        let operation = AttachmentDownloadOperation(file: file, download: download, progress: progress, userId: self.userId, apiClient: self.apiClient, webDavController: self.webDavController,
                                                    fileStorage: self.fileStorage, queue: self.queue)
        operation.finishedDownload = { [weak self] result in
            switch result {
            case .success:
                // Mark file as downloaded in DB
                try? self?.dbStorage.perform(request: MarkFileAsDownloadedDbRequest(key: download.key, libraryId: download.libraryId, downloaded: true))
            case .failure: break
            }

            inMainThread {
                self?.finish(download: download, parentKey: parentKey, result: result, hasLocalCopy: hasLocalCopy)
            }
        }

        self.errors[download] = nil
        self.progressObservers[download] = observer
        self.operations[download] = operation

        // Send first update to immediately reflect new state
        self.observable.on(.next(Update(download: download, parentKey: parentKey, kind: .progress(0))))
        // Add operation to queue
        self.operationQueue.addOperation(operation)
    }

    private func finish(download: Download, parentKey: String?, result: Result<(), Swift.Error>, hasLocalCopy: Bool) {
        self.operations[download] = nil
        self.progressObservers[download] = nil

        switch result {
        case .success:
            self.errors[download] = nil
            self.observable.on(.next(Update(download: download, parentKey: parentKey, kind: .ready)))

        case .failure(let error):
            DDLogError("AttachmentDownloader: failed to download attachment \(download.key), \(download.libraryId) - \(error)")

            let isCancelError = (error as? AttachmentDownloadOperation.Error) == .cancelled
            self.errors[download] = (isCancelError || hasLocalCopy) ? nil : error

            if isCancelError {
                self.observable.on(.next(Update(download: download, parentKey: parentKey, kind: .cancelled)))
            } else if hasLocalCopy {
                self.observable.on(.next(Update(download: download, parentKey: parentKey, kind: .ready)))
            } else {
                self.observable.on(.next(Update(download: download, parentKey: parentKey, kind: .failed(error))))
            }
        }
    }
}
