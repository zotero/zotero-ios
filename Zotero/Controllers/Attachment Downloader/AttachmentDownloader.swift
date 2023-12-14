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

final class AttachmentDownloader: NSObject {
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
    private let dbQueue: DispatchQueue
    private let disposeBag: DisposeBag
    let observable: PublishSubject<Update>

    private var session: URLSession!
    private var tasks: [Download: URLSessionTask]
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
            remainingBatchCount = self.tasks.count
            totalBatchCount = self.totalBatchCount
        }

        return (progress, remainingBatchCount, totalBatchCount)
    }

    init(userId: Int, apiClient: ApiClient, fileStorage: FileStorage, dbStorage: DbStorage, webDavController: WebDavController) {
        self.userId = userId
        self.fileStorage = fileStorage
        self.apiClient = apiClient
        self.dbStorage = dbStorage
        self.webDavController = webDavController
        self.tasks = [:]
        self.progressObservers = [:]
        self.accessQueue = DispatchQueue(label: "org.zotero.AttachmentDownloader.AccessQueue", qos: .userInteractive, attributes: .concurrent)
        self.dbQueue = DispatchQueue(label: "org.zotero.AttachmentDownloader.DbQueue", qos: .userInteractive)
        self.errors = [:]
        self.observable = PublishSubject()
        self.disposeBag = DisposeBag()

        super.init()

        self.session = URLSessionCreator.createSession(for: "AttachmentDownloaderBackgroundSession", delegate: self)
    }

    // MARK: - Actions

    func batchDownload(attachments: [(Attachment, String?)]) {
        self.accessQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            var tasks: [(Download, String?, URLSessionTask)] = []

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
                            guard let (download, task) = self.createDownload(file: file, key: attachment.key, parentKey: parentKey, libraryId: attachment.libraryId, hasLocalCopy: false) else { continue }
                            tasks.append((download, parentKey, task))
                        }
                    }
                }
            }

            for data in tasks {
                DDLogInfo("AttachmentDownloader: enqueue \(data.0.key)")
                // Send first update to immediately reflect new state
                self.observable.on(.next(Update(download: data.0, parentKey: data.1, kind: .progress(0))))
                data.2.resume()
            }
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

        guard let task = self.tasks[download] else { return }

        self.tasks[download] = nil
        self.batchProgress?.totalUnitCount -= 100
        self.resetBatchDataIfNeeded()
        task.cancel()

        DDLogInfo("AttachmentDownloader: cancelled \(download.key)")
    }

    func data(for key: String, libraryId: LibraryIdentifier) -> (progress: CGFloat?, error: Swift.Error?) {
        let download = Download(key: key, libraryId: libraryId)
        var progress: CGFloat?
        var error: Swift.Error?

        self.accessQueue.sync { [weak self] in
            progress = (self?.tasks[download]?.progress.fractionCompleted).flatMap({ CGFloat($0) })
            error = self?.errors[download]
        }

        return (progress, error)
    }

    private func resetBatchDataIfNeeded() {
        guard self.tasks.isEmpty else { return }
        self.totalBatchCount = 0
        self.batchProgress = nil
    }

    func stop() {
//        self.operationQueue.cancelAllOperations()
    }

    // MARK: - Helpers

    private func download(file: File, key: String, parentKey: String?, libraryId: LibraryIdentifier, hasLocalCopy: Bool) {
        self.accessQueue.async(flags: .barrier) { [weak self] in
            guard let self = self, let (download, task) = self.createDownload(file: file, key: key, parentKey: parentKey, libraryId: libraryId, hasLocalCopy: hasLocalCopy) else { return }
            DDLogInfo("AttachmentDownloader: enqueue \(download.key)")
            // Send first update to immediately reflect new state
            self.observable.on(.next(Update(download: download, parentKey: parentKey, kind: .progress(0))))
            // Resume task
            task.resume()
        }
    }

    private func createDownload(file: File, key: String, parentKey: String?, libraryId: LibraryIdentifier, hasLocalCopy: Bool) -> (Download, URLSessionTask)? {
        let download = Download(key: key, libraryId: libraryId)

        guard self.tasks[download] == nil else { return nil }

        do {
            let progress = Progress(totalUnitCount: 100)
            let observer = progress.observe(\.fractionCompleted) { [weak self] progress, _ in
                self?.observable.on(.next(Update(download: download, parentKey: parentKey, kind: .progress(CGFloat(progress.fractionCompleted)))))
            }
            let request = try apiClient.urlRequest(from: FileRequest(libraryId: libraryId, userId: userId, key: key, destination: file))
            let task = createTask(request: request, progress: progress, hasLocalCopy: hasLocalCopy)

            self.errors[download] = nil
            self.progressObservers[download] = observer
            self.tasks[download] = task
            self.totalBatchCount += 1

            if let batchProgress = self.batchProgress {
                batchProgress.addChild(progress, withPendingUnitCount: 100)
                batchProgress.totalUnitCount += 100
            } else {
                let batchProgress = Progress(totalUnitCount: 100)
                batchProgress.addChild(progress, withPendingUnitCount: 100)
                self.batchProgress = batchProgress
            }

            return (download, task)
        } catch let error {
            self.errors[download] = error
            self.progressObservers[download] = nil
            self.tasks[download] = nil
            self.observable.on(.next(.init(download: download, parentKey: parentKey, kind: .failed(error))))

            return nil
        }
    }

    private func createTask(request: URLRequest, progress: Progress, hasLocalCopy: Bool) -> URLSessionTask {
        // TODO: - Add webdav support
        let task = session.downloadTask(with: request)
        progress.addChild(task.progress, withPendingUnitCount: 50)
        return task
//        let operation = AttachmentDownloadOperation(
//            file: file,
//            download: download,
//            progress: progress,
//            userId: userId,
//            apiClient: apiClient,
//            webDavController: webDavController,
//            fileStorage: fileStorage,
//            queue: processingQueue
//        )
//        operation.finishedDownload = { [weak self] result in
//            guard let self = self else { return }
//
//            switch result {
//            case .success:
//                self.dbQueue.sync { [weak self] in
//                    guard let self = self else { return }
//                    // Mark file as downloaded in DB
//                    try? self.dbStorage.perform(request: MarkFileAsDownloadedDbRequest(key: download.key, libraryId: download.libraryId, downloaded: true), on: self.dbQueue)
//                }
//                self.finish(download: download, parentKey: parentKey, result: result, hasLocalCopy: hasLocalCopy)
//
//            case .failure:
//                self.finish(download: download, parentKey: parentKey, result: result, hasLocalCopy: hasLocalCopy)
//            }
//        }
    }

    private func finish(download: Download, parentKey: String?, result: Result<(), Swift.Error>, hasLocalCopy: Bool) {
//        self.accessQueue.async(flags: .barrier) { [weak self] in
//            self?._finish(download: download, parentKey: parentKey, result: result, hasLocalCopy: hasLocalCopy)
//        }
    }

    private func _finish(download: Download, parentKey: String?, result: Result<(), Swift.Error>, hasLocalCopy: Bool) {
//        self.operations[download] = nil
//        self.progressObservers[download] = nil
//        self.resetBatchDataIfNeeded()
//
//        switch result {
//        case .success:
//            DDLogInfo("AttachmentDownloader: finished downloading \(download.key)")
//
//            self.errors[download] = nil
//            self.observable.on(.next(Update(download: download, parentKey: parentKey, kind: .ready)))
//
//        case .failure(let error):
//            DDLogError("AttachmentDownloader: failed to download attachment \(download.key), \(download.libraryId) - \(error)")
//
//            let isCancelError = (error as? AttachmentDownloadOperation.Error) == .cancelled
//            self.errors[download] = (isCancelError || hasLocalCopy) ? nil : error
//
//            if isCancelError {
//                self.observable.on(.next(Update(download: download, parentKey: parentKey, kind: .cancelled)))
//            } else if hasLocalCopy {
//                self.observable.on(.next(Update(download: download, parentKey: parentKey, kind: .ready)))
//            } else {
//                self.observable.on(.next(Update(download: download, parentKey: parentKey, kind: .failed(error))))
//            }
//        }
    }
}

extension AttachmentDownloader: URLSessionDelegate {

}
