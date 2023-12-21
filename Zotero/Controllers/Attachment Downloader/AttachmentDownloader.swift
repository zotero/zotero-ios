//
//  AttachmentDownloader.swift
//  Zotero
//
//  Created by Michal Rentka on 11/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift
import RealmSwift
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
        
        fileprivate init(download: Download, kind: Kind) {
            self.key = download.key
            self.parentKey = download.parentKey
            self.libraryId = download.libraryId
            self.kind = kind
        }
    }

    struct Download: Hashable {
        let key: String
        let parentKey: String?
        let libraryId: LibraryIdentifier
    }

    private static let sessionId = "AttachmentDownloaderBackgroundSession"
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
    private var taskIdToDownload: [Int: Download]
    private var downloadToTaskId: [Download: Int]
    private var files: [Int: File]
    private var progresses: [Int: Progress]
    private var errors: [Download: Swift.Error]
    private var batchProgress: Progress?
    private var backgroundCompletionHandler: (() -> Void)?

    var batchData: (Progress?, Int, Int) {
        var progress: Progress?
        var totalBatchCount = 0
        var remainingBatchCount = 0

        self.accessQueue.sync { [weak self] in
            guard let self = self else { return }
            progress = self.batchProgress
            remainingBatchCount = self.downloadToTaskId.count
            totalBatchCount = Int((self.batchProgress?.totalUnitCount ?? 0) / 100)
        }

        return (progress, remainingBatchCount, totalBatchCount)
    }

    init(userId: Int, apiClient: ApiClient, fileStorage: FileStorage, dbStorage: DbStorage, webDavController: WebDavController) {
        self.userId = userId
        self.fileStorage = fileStorage
        self.apiClient = apiClient
        self.dbStorage = dbStorage
        self.webDavController = webDavController
        taskIdToDownload = [:]
        downloadToTaskId = [:]
        files = [:]
        progresses = [:]
        accessQueue = DispatchQueue(label: "org.zotero.AttachmentDownloader.AccessQueue", qos: .userInteractive, attributes: .concurrent)
        dbQueue = DispatchQueue(label: "org.zotero.AttachmentDownloader.DbQueue", qos: .userInteractive)
        errors = [:]
        observable = PublishSubject()
        disposeBag = DisposeBag()

        super.init()

        session = URLSessionCreator.createSession(for: Self.sessionId, delegate: self)
        session.getAllTasks { tasks in
            resumeDownloads(tasks: tasks)
        }

        func resumeDownloads(tasks: [URLSessionTask]) {
            var taskIds: Set<Int> = []
            for task in tasks {
                taskIds.insert(task.taskIdentifier)
            }

            dbQueue.async { [weak self] in
                let (cancelledTaskIds, downloadsInProgress, downloadsToRestore) = loadDatabaseDownloads(existingTaskIds: taskIds)
                DDLogInfo("AttachmentDownloader: cancel stored downloads - \(cancelledTaskIds.count)")
                for taskId in cancelledTaskIds {
                    guard let task = tasks.first(where: { $0.taskIdentifier == taskId }) else { continue }
                    task.cancel()
                }

                guard !downloadsInProgress.isEmpty || !downloadsToRestore.isEmpty else { return }

                self?.accessQueue.async(flags: .barrier) {
                    DDLogInfo("AttachmentDownloader: cache downloads in progress - \(downloadsInProgress.count); restore downloads - \(downloadsToRestore.count)")
                    self?.batchProgress = Progress(totalUnitCount: Int64(downloadsInProgress.count * 100))
                    storeDownloadData(for: downloadsInProgress)
                    let updatedDownloads = restore(downloads: downloadsToRestore)

                    guard !updatedDownloads.isEmpty else { return }

                    self?.dbQueue.async {
                        guard let self else { return }
                        let requests = updatedDownloads.map({ CreateEditDownloadDbRequest(taskId: $0.1, key: $0.0.key, parentKey: $0.0.parentKey, libraryId: $0.0.libraryId) })
                        do {
                            try dbStorage.perform(writeRequests: requests, on: self.dbQueue)
                        } catch let error {
                            DDLogError("AttachmentDownloader: can't update downloads - \(error)")
                        }
                    }
                }
            }
        }

        func loadDatabaseDownloads(existingTaskIds: Set<Int>) -> ([Int], [(Int, Download, File)], [(Download, File)]) {
            var cancelledTaskIds: [Int] = []
            var downloadsInProgress: [(Int, Download, File)] = []
            var downloadsToRestore: [(Download, File)] = []

            do {
                var toDelete: [Download] = []
                let downloads = try dbStorage.perform(request: ReadAllDownloadsDbRequest(), on: dbQueue)
                for rDownload in downloads {
                    guard let libraryId = rDownload.libraryId else { continue }

                    let download = Download(key: rDownload.key, parentKey: rDownload.parentKey, libraryId: libraryId)

                    guard let attachmentItem = try? dbStorage.perform(request: ReadItemDbRequest(libraryId: libraryId, key: rDownload.key), on: dbQueue),
                          let attachment = AttachmentCreator.attachment(for: attachmentItem, fileStorage: fileStorage, urlDetector: nil),
                          case .file(let filename, let contentType, _, _) = attachment.type else {
                        // Attachment item doesn't exist anymore, cancel download
                        toDelete.append(download)
                        cancelledTaskIds.append(rDownload.taskId)
                        continue
                    }

                    let file = Files.attachmentFile(in: attachment.libraryId, key: attachment.key, filename: filename, contentType: contentType)

                    if existingTaskIds.contains(rDownload.taskId) {
                        // Download is ongoing, cache data
                        downloadsInProgress.append((rDownload.taskId, Download(key: rDownload.key, parentKey: rDownload.parentKey, libraryId: libraryId), file))
                    } else {
                        // Download was cancelled by OS, restart download
                        downloadsToRestore.append((download, file))
                    }
                }

                let requests = toDelete.map({ DeleteDownloadDbRequest(key: $0.key, libraryId: $0.libraryId) })
                try dbStorage.perform(writeRequests: requests, on: dbQueue)
            } catch let error {
                DDLogError("AttachmentDownloader: can't load downloads - \(error)")
            }

            return (cancelledTaskIds, downloadsInProgress, downloadsToRestore)
        }

        func storeDownloadData(for downloads: [(Int, Download, File)]) {
            for (taskId, download, file) in downloads {
                DDLogInfo("AttachmentDownloader: cached \(taskId); \(download.key); (\(String(describing: download.parentKey))); \(download.libraryId)")
                downloadToTaskId[download] = taskId
                taskIdToDownload[taskId] = download
                let progress = Progress(totalUnitCount: 100)
                progresses[taskId] = progress
                batchProgress?.addChild(progress, withPendingUnitCount: 100)
                files[taskId] = file
            }
        }

        func restore(downloads: [(Download, File)]) -> [(Download, Int)] {
            var updatedTaskIds: [(Download, Int)] = []
            for (download, file) in downloads {
                guard let (_, task) = createDownload(file: file, key: download.key, parentKey: download.parentKey, libraryId: download.libraryId) else { continue }
                DDLogInfo("AttachmentDownloader: resumed \(task.taskIdentifier); \(download.key); (\(String(describing: download.parentKey))); \(download.libraryId)")
                updatedTaskIds.append((download, task.taskIdentifier))
                task.resume()
            }
            return updatedTaskIds
        }
    }

    // MARK: - Actions

    func handleEventsForBackgroundURLSession(with identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == Self.sessionId else { return }
        DDLogInfo("AttachmentDownloader: handle events for background url session \(identifier)")
        session = URLSessionCreator.createSession(for: identifier, delegate: self)
        backgroundCompletionHandler = completionHandler
    }

    func batchDownload(attachments: [(Attachment, String?)]) {
        accessQueue.async(flags: .barrier) { [weak self] in
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
                            guard let (download, task) = self.createDownload(file: file, key: attachment.key, parentKey: parentKey, libraryId: attachment.libraryId) else { continue }
                            tasks.append((download, parentKey, task))
                        }
                    }
                }
            }

            for data in tasks {
                DDLogInfo("AttachmentDownloader: enqueue \(data.0.key)")
                // Send first update to immediately reflect new state
                self.observable.on(.next(Update(download: data.0, kind: .progress(0))))
                data.2.resume()
            }
        }
    }

    func downloadIfNeeded(attachment: Attachment, parentKey: String?) {
        switch attachment.type {
        case .url:
            DDLogInfo("AttachmentDownloader: open url \(attachment.key)")
            observable.on(.next(Update(key: attachment.key, parentKey: parentKey, libraryId: attachment.libraryId, kind: .ready)))

        case .file(let filename, let contentType, let location, let linkType):
            switch linkType {
            case .linkedFile, .embeddedImage:
                DDLogWarn("AttachmentDownloader: tried opening linkedFile or embeddedImage \(attachment.key)")
                observable.on(.next(Update(key: attachment.key, parentKey: parentKey, libraryId: attachment.libraryId, kind: .failed(Error.incompatibleAttachment))))

            case .importedFile, .importedUrl:
                switch location {
                case .local:
                    DDLogInfo("AttachmentDownloader: open local file \(attachment.key)")
                    observable.on(.next(Update(key: attachment.key, parentKey: parentKey, libraryId: attachment.libraryId, kind: .ready)))

                case .remote, .remoteMissing:
                    DDLogInfo("AttachmentDownloader: download remote\(location == .remoteMissing ? "ly missing" : "") file \(attachment.key)")
                    let file = Files.attachmentFile(in: attachment.libraryId, key: attachment.key, filename: filename, contentType: contentType)
                    download(file: file, key: attachment.key, parentKey: parentKey, libraryId: attachment.libraryId)

                case .localAndChangedRemotely:
                    let file = Files.attachmentFile(in: attachment.libraryId, key: attachment.key, filename: filename, contentType: contentType)
                    if file.ext == "pdf" && fileStorage.has(file) && !fileStorage.isPdf(file: file) {
                        // Check whether downloaded file is actually a PDF, otherwise remove it. Fixes #483.
                        try? fileStorage.remove(file)
                        DDLogInfo("AttachmentDownloader: download remote file \(attachment.key). Fixed local PDF.")
                    } else {
                        DDLogInfo("AttachmentDownloader: download local file with remote change \(attachment.key)")
                    }
                    download(file: file, key: attachment.key, parentKey: parentKey, libraryId: attachment.libraryId)
                }
            }
        }
    }

    func cancel(key: String, parentKey: String?, libraryId: LibraryIdentifier) {
        let download = Download(key: key, parentKey: parentKey, libraryId: libraryId)
        var taskId: Int?
        accessQueue.sync { [weak self] in
            taskId = self?.downloadToTaskId[download]
        }
        guard let taskId else { return }
        session.getAllTasks { tasks in
            guard let task = tasks.first(where: { $0.taskIdentifier == taskId }) else { return }
            DDLogInfo("AttachmentDownloader: cancelled \(taskId)")
            task.cancel()
        }
    }

    func data(for key: String, parentKey: String?, libraryId: LibraryIdentifier) -> (progress: CGFloat?, error: Swift.Error?) {
        let download = Download(key: key, parentKey: parentKey, libraryId: libraryId)
        guard let taskId = downloadToTaskId[download] else { return (nil, nil) }
        var progress: CGFloat?
        var error: Swift.Error?
        accessQueue.sync { [weak self] in
            progress = (self?.progresses[taskId]?.fractionCompleted).flatMap({ CGFloat($0) })
            error = self?.errors[download]
        }
        return (progress, error)
    }

    private func resetBatchDataIfNeeded() {
        guard downloadToTaskId.isEmpty else { return }
        batchProgress = nil
        progresses = [:]
    }

    func stop() {
        DDLogInfo("AttachmentDownloader: stop all tasks")
        session.getAllTasks { tasks in
            for task in tasks {
                task.cancel()
            }
        }
    }

    // MARK: - Helpers

    private func download(file: File, key: String, parentKey: String?, libraryId: LibraryIdentifier) {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self = self, let (download, task) = self.createDownload(file: file, key: key, parentKey: parentKey, libraryId: libraryId) else { return }
            DDLogInfo("AttachmentDownloader: enqueue \(download.key)")
            do {
                let request = CreateEditDownloadDbRequest(taskId: task.taskIdentifier, key: download.key, parentKey: download.parentKey, libraryId: download.libraryId)
                try self.dbStorage.perform(request: request, on: self.accessQueue)
            } catch let error {
                DDLogError("AttachmentDownloader: couldn't store download to db - \(error)")
            }
            // Send first update to immediately reflect new state
            self.observable.on(.next(Update(download: download, kind: .progress(0))))
            // Resume task
            task.resume()
        }
    }

    private func createDownload(file: File, key: String, parentKey: String?, libraryId: LibraryIdentifier) -> (Download, URLSessionTask)? {
        let download = Download(key: key, parentKey: parentKey, libraryId: libraryId)

        guard downloadToTaskId[download] == nil else { return nil }

        do {
            let progress = Progress(totalUnitCount: 100)
            let request = try apiClient.urlRequest(from: FileRequest(libraryId: libraryId, userId: userId, key: key, destination: file))
            let task = session.downloadTask(with: request)

            DDLogInfo("AttachmentDownloader: create download of \(key); (\(String(describing: parentKey))); \(libraryId) = \(task.taskIdentifier)")

            downloadToTaskId[download] = task.taskIdentifier
            taskIdToDownload[task.taskIdentifier] = download
            files[task.taskIdentifier] = file
            progresses[task.taskIdentifier] = progress
            errors[download] = nil

            if let batchProgress {
                batchProgress.addChild(progress, withPendingUnitCount: 100)
                batchProgress.totalUnitCount += 100
            } else {
                let batchProgress = Progress(totalUnitCount: 100)
                batchProgress.addChild(progress, withPendingUnitCount: 100)
                self.batchProgress = batchProgress
            }

            return (download, task)
        } catch let error {
            errors[download] = error
            observable.on(.next(.init(download: download, kind: .failed(error))))
            return nil
        }
    }

    private func finish(download: Download, taskId: Int, result: Result<(), Swift.Error>) {
        let file = files[taskId]
        files[taskId] = nil
        downloadToTaskId[download] = nil
        taskIdToDownload[taskId] = nil
        resetBatchDataIfNeeded()

        DDLogInfo("AttachmentDownloader: finished downloading \(taskId); \(download.key); (\(String(describing: download.parentKey))); \(download.libraryId)")

        dbQueue.sync { [weak self] in
            guard let self = self else { return }
            do {
                try dbStorage.perform(request: DeleteDownloadDbRequest(key: download.key, libraryId: download.libraryId), on: self.dbQueue)
            } catch let error {
                DDLogError("AttachmentDownloader: could not remove download from db - \(error)")
            }
        }

        switch result {
        case .success:
            errors[download] = nil
            progresses[taskId]?.completedUnitCount = 100
            observable.on(.next(Update(download: download, kind: .ready)))

        case .failure(let error):
            if (error as NSError).code == NSURLErrorCancelled {
                errors[download] = nil
                progresses[taskId] = nil
                batchProgress?.totalUnitCount -= 100
                observable.on(.next(Update(download: download, kind: .cancelled)))
            } else if file.flatMap({ fileStorage.has($0) }) ?? false {
                DDLogError("AttachmentDownloader: failed to download remotely changed attachment \(taskId) - \(error)")
                errors[download] = nil
                progresses[taskId]?.completedUnitCount = 100
                observable.on(.next(Update(download: download, kind: .ready)))
            } else {
                DDLogError("AttachmentDownloader: failed to download attachment \(taskId) - \(error)")
                errors[download] = error
                progresses[taskId]?.completedUnitCount = 100
                observable.on(.next(Update(download: download, kind: .failed(error))))
            }
        }
    }
}

extension AttachmentDownloader: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        var download: Download?
        var file: File?
        accessQueue.sync { [weak self] in
            download = self?.taskIdToDownload[downloadTask.taskIdentifier]
            file = self?.files[downloadTask.taskIdentifier]
        }

        guard let file, let download else {
            DDLogError("AttachmentDownloader: didFinishDownloadingTo \(downloadTask.taskIdentifier) not found")
            return
        }

        do {
            var isCompressed = false
            if let response = downloadTask.response as? HTTPURLResponse {
                isCompressed = response.value(forHTTPHeaderField: "Zotero-File-Compressed") == "Yes"
            }

            DDLogInfo("AttachmentDownloader: didFinishDownloadingTo \(downloadTask.taskIdentifier); compressed=\(isCompressed)")

            try fileStorage.move(from: location.path, to: file)

            dbQueue.sync { [weak self] in
                guard let self = self else { return }
                // Mark file as downloaded in DB
                try? self.dbStorage.perform(request: MarkFileAsDownloadedDbRequest(key: download.key, libraryId: download.libraryId, downloaded: true), on: self.dbQueue)
            }

            accessQueue.sync(flags: .barrier) { [weak self] in
                self?.finish(download: download, taskId: downloadTask.taskIdentifier, result: .success(()))
            }
        } catch let error {
            accessQueue.sync(flags: .barrier) { [weak self] in
                self?.finish(download: download, taskId: downloadTask.taskIdentifier, result: .failure(error))
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Swift.Error?) {
        accessQueue.sync(flags: .barrier) { [weak self] in
            guard let self, let error, let download = taskIdToDownload[task.taskIdentifier] else { return }
            self.finish(download: download, taskId: task.taskIdentifier, result: .failure(error))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        var progress: Progress?
        var download: Download?
        accessQueue.sync {
            progress = progresses[downloadTask.taskIdentifier]
            download = taskIdToDownload[downloadTask.taskIdentifier]
        }
        guard let progress, let download else { return }
        progress.completedUnitCount = Int64(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) * 100)
        DDLogInfo("AttachmentDownloader: download progress \(progress.fractionCompleted); \(downloadTask.taskIdentifier)")
        observable.on(.next(Update(download: download, kind: .progress(CGFloat(progress.fractionCompleted)))))
    }
}

extension AttachmentDownloader: URLSessionDelegate {
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DDLogInfo("AttachmentDownloader: urlSessionDidFinishEvents for background session")
        inMainThread { [weak self] in
            self?.backgroundCompletionHandler?()
            self?.backgroundCompletionHandler = nil
        }
    }
}
