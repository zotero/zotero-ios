//
//  AttachmentDownloader.swift
//  Zotero
//
//  Created by Michal Rentka on 11/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift
import RxSwift
import ZIPFoundation

final class AttachmentDownloader {
    enum Error: Swift.Error {
        case incompatibleAttachment
        case zipDidntContainRequestedFile
        case cantUnzipSnapshot
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
    private let accessQueue: DispatchQueue
    private let processingQueue: DispatchQueue
    // Database requests have to be performed on serial queue, since `processingQueue` is concurrent to allow multiple downloads, db requests need their separate queue.
    private let dbQueue: DispatchQueue
    private let operationQueue: OperationQueue
    private let disposeBag: DisposeBag
    let observable: PublishSubject<Update>

    private var operations: [Download: AttachmentDownloadOperation]
    private var progressObservers: [Download: NSKeyValueObservation]
    private var errors: [Download: Swift.Error]
    private var batchProgress: Progress?
    private var totalBatchCount: Int = 0

    var batchData: (Progress?, Int, Int) {
        var progress: Progress?
        var totalBatchCount = 0
        var remainingBatchCount = 0

        self.accessQueue.sync { [weak self] in
            guard let self = self else { return }
            progress = self.batchProgress
            remainingBatchCount = self.operations.count
            totalBatchCount = self.totalBatchCount
        }

        return (progress, remainingBatchCount, totalBatchCount)
    }

    init(userId: Int, apiClient: ApiClient, fileStorage: FileStorage, dbStorage: DbStorage, webDavController: WebDavController) {
        let processingQueue = DispatchQueue(label: "org.zotero.AttachmentDownloader.ProcessingQueue", qos: .userInteractive, attributes: .concurrent)
        let operationQueue = OperationQueue()
        operationQueue.maxConcurrentOperationCount = 2
        operationQueue.qualityOfService = .userInitiated
        operationQueue.underlyingQueue = processingQueue

        self.userId = userId
        self.apiClient = apiClient
        self.fileStorage = fileStorage
        self.dbStorage = dbStorage
        self.webDavController = webDavController
        self.operations = [:]
        self.progressObservers = [:]
        self.accessQueue = DispatchQueue(label: "org.zotero.AttachmentDownloader.AccessQueue", qos: .userInteractive, attributes: .concurrent)
        self.dbQueue = DispatchQueue(label: "org.zotero.AttachmentDownloader.DbQueue", qos: .userInteractive)
        self.processingQueue = processingQueue
        self.operationQueue = operationQueue
        self.errors = [:]
        self.observable = PublishSubject()
        self.disposeBag = DisposeBag()
    }

    // MARK: - Actions

    func batchDownload(attachments: [(Attachment, String?)]) {
        self.accessQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            var operations: [(Download, String?, AttachmentDownloadOperation)] = []

            for (attachment, parentKey) in attachments {
                switch attachment.type {
                case .url: break

                case .file(let filename, let contentType, let location, let linkType):
                    switch linkType {
                    case .linkedFile, .embeddedImage:
                        break

                    case .importedFile, .importedUrl:
                        switch location {
                        case .local:
                            break

                        case .remote, .remoteMissing, .localAndChangedRemotely:
                            DDLogInfo("AttachmentDownloader: batch download remote\(location == .remoteMissing ? "ly missing" : "") file \(attachment.key)")
                            let file = Files.attachmentFile(in: attachment.libraryId, key: attachment.key, filename: filename, contentType: contentType)
                            guard let (download, operation) = self.createDownload(file: file, key: attachment.key, parentKey: parentKey, libraryId: attachment.libraryId, hasLocalCopy: false) else { continue }
                            operations.append((download, parentKey, operation))
                        }
                    }
                }
            }

            for data in operations {
                DDLogInfo("AttachmentDownloader: enqueue \(data.0.key)")
                // Send first update to immediately reflect new state
                self.observable.on(.next(Update(download: data.0, parentKey: data.1, kind: .progress(0))))
            }

            let downloadOperations = operations.map({ $0.2 })
            self.operationQueue.addOperations(downloadOperations, waitUntilFinished: false)
        }
    }

    func downloadIfNeeded(attachment: Attachment, parentKey: String?) {
        switch attachment.type {
        case .url:
            DDLogInfo("AttachmentDownloader: open url \(attachment.key)")
            self.observable.on(.next(Update(key: attachment.key, parentKey: parentKey, libraryId: attachment.libraryId, kind: .ready)))

        case .file(let filename, let contentType, let location, let linkType):
            switch linkType {
            case .linkedFile, .embeddedImage:
                DDLogWarn("AttachmentDownloader: tried opening linkedFile or embeddedImage \(attachment.key)")
                self.observable.on(.next(Update(key: attachment.key, parentKey: parentKey, libraryId: attachment.libraryId, kind: .failed(Error.incompatibleAttachment))))

            case .importedFile, .importedUrl:
                switch location {
                case .local:
                    DDLogInfo("AttachmentDownloader: open local file \(attachment.key)")
                    self.observable.on(.next(Update(key: attachment.key, parentKey: parentKey, libraryId: attachment.libraryId, kind: .ready)))

                case .remote, .remoteMissing:
                    DDLogInfo("AttachmentDownloader: download remote\(location == .remoteMissing ? "ly missing" : "") file \(attachment.key)")

                    let file = Files.attachmentFile(in: attachment.libraryId, key: attachment.key, filename: filename, contentType: contentType)
                    self.download(file: file, key: attachment.key, parentKey: parentKey, libraryId: attachment.libraryId, hasLocalCopy: false)

                case .localAndChangedRemotely:
                    let file = Files.attachmentFile(in: attachment.libraryId, key: attachment.key, filename: filename, contentType: contentType)

                    var hasLocalCopy = true

                    // Fixes a bug (#483) where attachment downloader downloaded an xml or other file even if the download request failed. This checks whether the file is actually a PDF. For other file types, users will just have to deal with it.
                    if file.ext == "pdf" && self.fileStorage.has(file) && !self.fileStorage.isPdf(file: file) {
                        try? self.fileStorage.remove(file)
                        hasLocalCopy = false
                    }

                    if hasLocalCopy {
                        DDLogInfo("AttachmentDownloader: download local file with remote change \(attachment.key)")
                    } else {
                        DDLogInfo("AttachmentDownloader: download remote file \(attachment.key). Fixed local PDF.")
                    }

                    self.download(file: file, key: attachment.key, parentKey: parentKey, libraryId: attachment.libraryId, hasLocalCopy: hasLocalCopy)
                }
            }
        }
    }

    func cancel(key: String, libraryId: LibraryIdentifier) {
        self.accessQueue.async(flags: .barrier) { [weak self] in
            self?._cancel(key: key, libraryId: libraryId)
        }
    }

    private func _cancel(key: String, libraryId: LibraryIdentifier) {
        let download = Download(key: key, libraryId: libraryId)
        self.progressObservers[download] = nil

        guard let operation = self.operations[download] else { return }

        self.operations[download] = nil
        self.batchProgress?.totalUnitCount -= 100
        self.resetBatchDataIfNeeded()

        DDLogInfo("AttachmentDownloader: cancelled \(download.key)")

        self.processingQueue.async {
            operation.cancel()
        }
    }

    func data(for key: String, libraryId: LibraryIdentifier) -> (progress: CGFloat?, error: Swift.Error?) {
        let download = Download(key: key, libraryId: libraryId)
        var progress: CGFloat?
        var error: Swift.Error?

        self.accessQueue.sync { [weak self] in
            progress = (self?.operations[download]?.progress.fractionCompleted).flatMap({ CGFloat($0) })
            error = self?.errors[download]
        }

        return (progress, error)
    }

    private func resetBatchDataIfNeeded() {
        guard self.operations.isEmpty else { return }
        self.totalBatchCount = 0
        self.batchProgress = nil
    }

    func stop() {
        self.operationQueue.cancelAllOperations()
    }

    // MARK: - Helpers

    private func download(file: File, key: String, parentKey: String?, libraryId: LibraryIdentifier, hasLocalCopy: Bool) {
        self.accessQueue.async(flags: .barrier) { [weak self] in
            guard let self = self, let (download, operation) = self.createDownload(file: file, key: key, parentKey: parentKey, libraryId: libraryId, hasLocalCopy: hasLocalCopy) else { return }
            self.enqueue(operation: operation, download: download, parentKey: parentKey)
        }
    }

    private func enqueue(operation: AttachmentDownloadOperation, download: Download, parentKey: String?) {
        DDLogInfo("AttachmentDownloader: enqueue \(download.key)")
        // Send first update to immediately reflect new state
        self.observable.on(.next(Update(download: download, parentKey: parentKey, kind: .progress(0))))
        // Add operation to queue
        self.operationQueue.addOperation(operation)
    }

    private func createDownload(file: File, key: String, parentKey: String?, libraryId: LibraryIdentifier, hasLocalCopy: Bool) -> (Download, AttachmentDownloadOperation)? {
        let download = Download(key: key, libraryId: libraryId)

        guard self.operations[download] == nil else { return nil }

        let progress = Progress(totalUnitCount: 100)
        let observer = progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            self?.observable.on(.next(Update(download: download, parentKey: parentKey, kind: .progress(CGFloat(progress.fractionCompleted)))))
        }
        let operation = AttachmentDownloadOperation(
            file: file,
            download: download,
            progress: progress,
            userId: userId,
            apiClient: apiClient,
            webDavController: webDavController,
            fileStorage: fileStorage,
            queue: processingQueue
        )
        operation.finishedDownload = { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success:
                self.dbQueue.sync { [weak self] in
                    guard let self = self else { return }
                    // Mark file as downloaded in DB
                    try? self.dbStorage.perform(request: MarkFileAsDownloadedDbRequest(key: download.key, libraryId: download.libraryId, downloaded: true), on: self.dbQueue)
                }
                self.finish(download: download, parentKey: parentKey, result: result, hasLocalCopy: hasLocalCopy)
                
            case .failure:
                self.finish(download: download, parentKey: parentKey, result: result, hasLocalCopy: hasLocalCopy)
            }
        }

        self.errors[download] = nil
        self.progressObservers[download] = observer
        self.operations[download] = operation
        self.totalBatchCount += 1

        if let batchProgress = self.batchProgress {
            batchProgress.addChild(progress, withPendingUnitCount: 100)
            batchProgress.totalUnitCount += 100
        } else {
            let batchProgress = Progress(totalUnitCount: 100)
            batchProgress.addChild(progress, withPendingUnitCount: 100)
            self.batchProgress = batchProgress
        }

        return (download, operation)
    }

    private func finish(download: Download, parentKey: String?, result: Result<(), Swift.Error>, hasLocalCopy: Bool) {
        self.accessQueue.async(flags: .barrier) { [weak self] in
            self?._finish(download: download, parentKey: parentKey, result: result, hasLocalCopy: hasLocalCopy)
        }
    }

    private func _finish(download: Download, parentKey: String?, result: Result<(), Swift.Error>, hasLocalCopy: Bool) {
        self.operations[download] = nil
        self.progressObservers[download] = nil
        self.resetBatchDataIfNeeded()

        switch result {
        case .success:
            DDLogInfo("AttachmentDownloader: finished downloading \(download.key)")

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
