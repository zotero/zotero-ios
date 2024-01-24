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

    private struct EnqueuedDownload {
        let download: Download
        let file: File
        let progress: Progress
        let extractAfterDownload: Bool
    }

    private struct DownloadInProgress {
        let taskId: Int
        let file: File
        let progress: Progress
        let extractAfterDownload: Bool
        let logData: ApiLogger.StartData?
    }

    private static let maxConcurrentDownloads = 4
    private static let sessionId = "AttachmentDownloaderBackgroundSession"
    private let userId: Int
    private unowned let apiClient: ApiClient
    private unowned let fileStorage: FileStorage
    private unowned let dbStorage: DbStorage
    private unowned let webDavController: WebDavController
    private let accessQueue: DispatchQueue
    private let dbQueue: DispatchQueue
    private let unzipQueue: DispatchQueue
    private let disposeBag: DisposeBag
    let observable: PublishSubject<Update>

    private var session: URLSession!
    private var queue: [EnqueuedDownload]
    private var activeDownloads: [Download: DownloadInProgress]
    private var extractionObservers: [Download: NSKeyValueObservation]
    private var totalCount: Int
    private var errors: [Download: Swift.Error]
    private var initialErrors: [Int: Swift.Error]
    private var batchProgress: Progress?
    private var backgroundCompletionHandler: (() -> Void)?

    var batchData: (Progress?, Int, Int) {
        var progress: Progress?
        var totalBatchCount = 0
        var remainingBatchCount = 0

        self.accessQueue.sync { [weak self] in
            guard let self = self else { return }
            progress = batchProgress
            remainingBatchCount = queue.count + activeDownloads.count
            totalBatchCount = totalCount
        }

        return (progress, remainingBatchCount, totalBatchCount)
    }

    init(userId: Int, apiClient: ApiClient, fileStorage: FileStorage, dbStorage: DbStorage, webDavController: WebDavController) {
        self.userId = userId
        self.fileStorage = fileStorage
        self.apiClient = apiClient
        self.dbStorage = dbStorage
        self.webDavController = webDavController
        queue = []
        totalCount = 0
        errors = [:]
        initialErrors = [:]
        accessQueue = DispatchQueue(label: "org.zotero.AttachmentDownloader.AccessQueue", qos: .userInteractive, attributes: .concurrent)
        dbQueue = DispatchQueue(label: "org.zotero.AttachmentDownloader.DbQueue", qos: .userInteractive)
        unzipQueue = DispatchQueue(label: "org.zotero.AttachmentDownloader.UnzipQueue", qos: .userInteractive, attributes: .concurrent)
        observable = PublishSubject()
        disposeBag = DisposeBag()

        super.init()

        session = URLSessionCreator.createSession(for: Self.sessionId, delegate: self, httpMaximumConnectionsPerHost: 1)
        session.getAllTasks { tasks in
            resumeDownloads(tasks: tasks)
        }

        NotificationCenter.default
            .rx
            .notification(.attachmentFileDeleted)
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] notification in
                guard let self, let notification = notification.object as? AttachmentFileDeletedNotification else {
                    return
                }
                handleDeletedAttachments(notification: notification, self: self)
            })
            .disposed(by: disposeBag)

        func resumeDownloads(tasks: [URLSessionTask]) {
            var taskIds: Set<Int> = []
            for task in tasks {
                taskIds.insert(task.taskIdentifier)
            }

            dbQueue.async { [weak self] in
                let (cancelledTaskIds, activeDownloads, downloadsToRestore) = loadDatabaseDownloads(existingTaskIds: taskIds)

                DDLogInfo("AttachmentDownloader: cancel stored downloads - \(cancelledTaskIds.count)")
                for taskId in cancelledTaskIds {
                    guard let task = tasks.first(where: { $0.taskIdentifier == taskId }) else { continue }
                    task.cancel()
                }

                guard !activeDownloads.isEmpty || !downloadsToRestore.isEmpty else { return }

                self?.accessQueue.async(flags: .barrier) { [weak self] in
                    guard let self else { return }

                    DDLogInfo("AttachmentDownloader: cache downloads in progress - \(activeDownloads.count); restore downloads - \(downloadsToRestore.count)")

                    batchProgress = Progress()
                    let failedDownloads = storeDownloadData(for: activeDownloads)
                    queue = downloadsToRestore

                    for download in activeDownloads.filter({ activeDownloadData in !failedDownloads.contains(where: { $0.0 == activeDownloadData.1.download }) }) {
                        observable.on(.next(Update(download: download.1.download, kind: .progress(0))))
                    }
                    for download in downloadsToRestore {
                        addProgressToBatchProgress(progress: download.progress)
                        observable.on(.next(Update(download: download.download, kind: .progress(0))))
                    }

                    startNextDownloadIfPossible()

                    guard !failedDownloads.isEmpty else { return }

                    for failed in failedDownloads {
                        observable.on(.next(Update(download: failed.0, kind: .failed(failed.1))))
                    }

                    dbQueue.async { [weak self] in
                        guard let self else { return }
                        do {
                            let requests = failedDownloads.map({ DeleteDownloadDbRequest(key: $0.0.key, libraryId: $0.0.libraryId) })
                            try dbStorage.perform(writeRequests: requests, on: dbQueue)
                        } catch let error {
                            DDLogError("AttachmentDownloader: can't update downloads - \(error)")
                        }
                    }
                }
            }
        }

        func loadDatabaseDownloads(existingTaskIds: Set<Int>) -> (Set<Int>, [(Int, EnqueuedDownload)], [EnqueuedDownload]) {
            var cancelledTaskIds: Set<Int> = []
            var activeDownloads: [(Int, EnqueuedDownload)] = []
            var downloadsToRestore: [EnqueuedDownload] = []

            do {
                var toDelete: [Download] = []
                let downloads = try dbStorage.perform(request: ReadAllDownloadsDbRequest(), on: dbQueue)
                for rDownload in downloads {
                    guard let libraryId = rDownload.libraryId else { continue }

                    let download = Download(key: rDownload.key, parentKey: rDownload.parentKey, libraryId: libraryId)

                    guard let attachmentItem = try? dbStorage.perform(request: ReadItemDbRequest(libraryId: libraryId, key: rDownload.key), on: dbQueue),
                          let attachment = AttachmentCreator.attachment(for: attachmentItem, fileStorage: fileStorage, urlDetector: nil),
                          case .file(let filename, let contentType, _, _, _) = attachment.type else {
                        // Attachment item doesn't exist anymore, cancel download
                        toDelete.append(download)
                        if let taskId = rDownload.taskId {
                            cancelledTaskIds.insert(taskId)
                        }
                        continue
                    }

                    let file = Files.attachmentFile(in: attachment.libraryId, key: attachment.key, filename: filename, contentType: contentType)

                    if let taskId = rDownload.taskId, existingTaskIds.contains(taskId) {
                        // Download is ongoing, cache data
                        activeDownloads.append((taskId, EnqueuedDownload(download: download, file: file, progress: Progress(), extractAfterDownload: false)))
                    } else {
                        // Download was cancelled by OS, restart download
                        downloadsToRestore.append(EnqueuedDownload(download: download, file: file, progress: Progress(), extractAfterDownload: false))
                    }
                }

                let requests = toDelete.map({ DeleteDownloadDbRequest(key: $0.key, libraryId: $0.libraryId) })
                try dbStorage.perform(writeRequests: requests, on: dbQueue)
            } catch let error {
                DDLogError("AttachmentDownloader: can't load downloads - \(error)")
            }

            return (cancelledTaskIds, activeDownloads, downloadsToRestore)
        }

        func storeDownloadData(for downloads: [(Int, EnqueuedDownload)]) -> [(Download, Swift.Error)] {
            var failed: [(Download, Swift.Error)] = []
            for (taskId, enqueuedDownload) in downloads {
                DDLogInfo("AttachmentDownloader: cached \(taskId); \(enqueuedDownload.download.key); (\(enqueuedDownload.download.parentKey ?? "-")); \(enqueuedDownload.download.libraryId)")
                let progress = Progress(totalUnitCount: 100)
                batchProgress?.addChild(progress, withPendingUnitCount: 100)
                totalCount += 1
                if let error = initialErrors[taskId] {
                    errors[enqueuedDownload.download] = error
                    progress.completedUnitCount = 100
                    failed.append((enqueuedDownload.download, error))
                }
                activeDownloads[enqueuedDownload.download] = DownloadInProgress(taskId: taskId, file: enqueuedDownload.file, progress: progress, extractAfterDownload: false, logData: nil)
            }
            return failed
        }

        func handleDeletedAttachments(notification: AttachmentFileDeletedNotification, self: AttachmentDownloader) {
            switch notification {
            case .individual(let key, let parentKey, let libraryId):
                self.cancel(key: key, parentKey: parentKey, libraryId: libraryId)

            case .allForItems(let keys, let libraryId):
                self.dbQueue.async { [weak self] in
                    guard let self else { return }
                    do {
                        let downloads = try self.dbStorage.perform(request: DeleteDownloadsDbRequest(keys: keys, libraryId: libraryId), on: self.dbQueue)
                        self.cancel(downloads: downloads)
                    } catch let error {
                        DDLogError("AttachmentDownloader: can't delete downloads for \(keys); \(libraryId) - \(error)")
                    }
                }

            case .library(let libraryId):
                self.dbQueue.async { [weak self] in
                    guard let self else { return }
                    do {
                        let downloads = try self.dbStorage.perform(request: DeleteLibraryDownloadsDbRequest(libraryId: libraryId), on: self.dbQueue)
                        self.cancel(downloads: downloads)
                    } catch let error {
                        DDLogError("AttachmentDownloader: can't delete downloads for \(libraryId) - \(error)")
                    }
                }

            case .all:
                self.cancelAll()
            }
        }
    }

    // MARK: - Actions

    func handleEventsForBackgroundURLSession(with identifier: String, completionHandler: @escaping () -> Void) -> Bool {
        guard identifier == Self.sessionId else { return false }
        DDLogInfo("AttachmentDownloader: handle events for background url session \(identifier)")
        backgroundCompletionHandler = completionHandler
        session = URLSessionCreator.createSession(for: identifier, delegate: self)
        return true
    }

    func batchDownload(attachments: [(Attachment, String?)]) {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }

            var downloads: [EnqueuedDownload] = []
            for (attachment, parentKey) in attachments {
                switch attachment.type {
                case .url: break

                case .file(let filename, let contentType, let location, let linkType, _):
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
                            let progress = Progress(totalUnitCount: 100)
                            let download = Download(key: attachment.key, parentKey: parentKey, libraryId: attachment.libraryId)
                            addProgressToBatchProgress(progress: progress)
                            downloads.append(EnqueuedDownload(download: download, file: file, progress: progress, extractAfterDownload: false))
                            observable.on(.next(Update(download: download, kind: .progress(0))))
                        }
                    }
                }
            }

            dbQueue.async { [weak self] in
                guard let self else { return }
                do {
                    let requests: [DbRequest] = downloads.map({ CreateEditDownloadDbRequest(taskId: nil, key: $0.download.key, parentKey: $0.download.parentKey, libraryId: $0.download.libraryId) })
                    try dbStorage.perform(writeRequests: requests, on: dbQueue)
                } catch let error {
                    DDLogError("AttachmentDownloader: couldn't store downloads to db - \(error)")
                }
            }

            queue.append(contentsOf: downloads)
            startNextDownloadIfPossible()
        }
    }

    func downloadIfNeeded(attachment: Attachment, parentKey: String?) {
        switch attachment.type {
        case .url:
            DDLogInfo("AttachmentDownloader: open url \(attachment.key)")
            observable.on(.next(Update(key: attachment.key, parentKey: parentKey, libraryId: attachment.libraryId, kind: .ready)))

        case .file(let filename, let contentType, let location, let linkType, let compressed):
            switch linkType {
            case .linkedFile, .embeddedImage:
                DDLogWarn("AttachmentDownloader: tried opening linkedFile or embeddedImage \(attachment.key)")
                observable.on(.next(Update(key: attachment.key, parentKey: parentKey, libraryId: attachment.libraryId, kind: .failed(Error.incompatibleAttachment))))

            case .importedFile, .importedUrl:
                switch location {
                case .local:
                    if compressed {
                        let file = Files.attachmentFile(in: attachment.libraryId, key: attachment.key, filename: filename, contentType: contentType)
                        extract(zipFile: file.copyWithExt("zip"), toFile: file, download: Download(key: attachment.key, parentKey: parentKey, libraryId: attachment.libraryId))
                    } else {
                        DDLogInfo("AttachmentDownloader: open local file \(attachment.key)")
                        observable.on(.next(Update(key: attachment.key, parentKey: parentKey, libraryId: attachment.libraryId, kind: .ready)))
                    }

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

        func download(file: File, key: String, parentKey: String?, libraryId: LibraryIdentifier) {
            accessQueue.async(flags: .barrier) { [weak self] in
                guard let self else { return }

                DDLogInfo("AttachmentDownloader: enqueue \(key)")

                dbQueue.async { [weak self] in
                    guard let self else { return }
                    do {
                        let request = CreateEditDownloadDbRequest(taskId: nil, key: key, parentKey: parentKey, libraryId: libraryId)
                        try dbStorage.perform(request: request, on: dbQueue)
                    } catch let error {
                        DDLogError("AttachmentDownloader: couldn't store download to db - \(error)")
                    }
                }

                let progress = Progress(totalUnitCount: 100)
                addProgressToBatchProgress(progress: progress)
                let download = EnqueuedDownload(download: Download(key: key, parentKey: parentKey, libraryId: libraryId), file: file, progress: progress, extractAfterDownload: true)
                queue.insert(download, at: 0)
                observable.on(.next(Update(download: download.download, kind: .progress(0))))
                startNextDownloadIfPossible()
            }
        }
    }

    private func extract(zipFile: File, toFile file: File, download: Download) {
        accessQueue.async { [weak self] in
            guard let self, let activeDownload = activeDownloads[download] else { return }
            // Reset progress for extraction
            activeDownload.progress.completedUnitCount = 0
            unzipQueue.async { [weak self] in
                guard let self else { return }
                extract(zipFile: zipFile, toFile: file, progress: activeDownload.progress, download: download, self: self)
            }
        }

        func extract(zipFile: File, toFile file: File, progress: Progress, download: Download, self: AttachmentDownloader) {
            do {
                // Check whether zip file exists
                if !self.fileStorage.has(zipFile) {
                    // Check whether file exists
                    if !self.fileStorage.has(file) {
                        throw AttachmentDownloader.Error.cantUnzipSnapshot
                    }

                    // Try removing zip file, don't return error if it fails, we've got what we wanted.
                    try? self.fileStorage.remove(zipFile)
                    finishExtraction(self: self)
                    return
                }

                // Send first progress update
                self.observable.on(.next(Update(download: download, kind: .progress(0))))
                // Remove other contents of folder so that zip extraction doesn't fail
                let files: [File] = try self.fileStorage.contentsOfDirectory(at: zipFile.directory)
                for file in files {
                    guard file.name != zipFile.name || file.ext != zipFile.ext else { continue }
                    try? self.fileStorage.remove(file)
                }
                let observer = progress.observe(\.fractionCompleted) { [weak self] progress, _ in
                    self?.observable.on(.next(Update(download: download, kind: .progress(CGFloat(progress.fractionCompleted)))))
                }
                self.accessQueue.sync(flags: .barrier) { [weak self] in
                    self?.extractionObservers[download] = observer
                }
                // Unzip to same directory
                try FileManager.default.unzipItem(at: zipFile.createUrl(), to: zipFile.createRelativeUrl(), progress: progress)
                // Try removing zip file, don't return error if it fails, we've got what we wanted.
                try? self.fileStorage.remove(zipFile)
                // Rename unzipped file if zip contained only 1 file and the names don't match
                let unzippedFiles: [File] = try self.fileStorage.contentsOfDirectory(at: file.directory)
                if unzippedFiles.count == 1, let unzipped = unzippedFiles.first, (unzipped.name != file.name) || (unzipped.ext != file.ext) {
                    try? self.fileStorage.move(from: unzipped, to: file)
                }
                // Check whether file exists
                if !self.fileStorage.has(file) {
                    throw AttachmentDownloader.Error.zipDidntContainRequestedFile
                }

                finishExtraction(self: self)
            } catch let error {
                DDLogError("AttachmentDownloader: unzip error - \(error)")

                if let error = error as? AttachmentDownloader.Error {
                    report(error: error, self: self)
                } else {
                    report(error: AttachmentDownloader.Error.cantUnzipSnapshot, self: self)
                }
            }

            func finishExtraction(self: AttachmentDownloader) {
                self.dbQueue.async { [weak self] in
                    guard let self else { return }

                    do {
                        try dbStorage.perform(request: MarkFileAsDownloadedDbRequest(key: download.key, libraryId: download.libraryId, downloaded: true, compressed: false), on: dbQueue)

                        self.accessQueue.async(flags: .barrier) { [weak self] in
                            guard let self else { return }
                            extractionObservers[download] = nil
                            activeDownloads[download] = nil
                            resetBatchDataIfNeeded()
                            observable.on(.next(Update(download: download, kind: .ready)))
                            startNextDownloadIfPossible()
                        }
                    } catch let error {
                        DDLogError("AttachmentDownloader: can't store new compressed value - \(error)")
                        report(error: AttachmentDownloader.Error.cantUnzipSnapshot, self: self)
                    }
                }
            }

            func report(error: Error, self: AttachmentDownloader) {
                self.accessQueue.async(flags: .barrier) { [weak self] in
                    guard let self else { return }
                    errors[download] = error
                    extractionObservers[download] = nil
                    activeDownloads[download] = nil
                    resetBatchDataIfNeeded()
                    observable.on(.next(Update(download: download, kind: .failed(error))))
                    startNextDownloadIfPossible()
                }
            }
        }
    }

    func cancel(key: String, parentKey: String?, libraryId: LibraryIdentifier) {
        let download = Download(key: key, parentKey: parentKey, libraryId: libraryId)
        cancel(downloads: [download])

        dbQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.dbStorage.perform(request: DeleteDownloadDbRequest(key: key, libraryId: libraryId), on: self.dbQueue)
            } catch let error {
                DDLogError("AttachmentDownloader: can't delete download \(key); \(String(describing: parentKey)); \(libraryId) - \(error)")
            }
        }
    }

    private func cancel(downloads: Set<Download>) {
        var taskId: Int?

        accessQueue.sync(flags: .barrier) { [weak self] in
            guard let self else { return }
            for download in downloads {
                if let activeDownload = activeDownloads[download] {
                    activeDownloads[download] = nil
                    extractionObservers[download] = nil
                    taskId = activeDownload.taskId
                } else if let index = queue.firstIndex(where: { $0.download == download }) {
                    queue.remove(at: index)
                } else {
                    continue
                }
                errors[download] = nil
                batchProgress?.totalUnitCount -= 100
                totalCount -= 1
            }
            resetBatchDataIfNeeded()
            startNextDownloadIfPossible()
        }

        if let taskId {
            session?.getAllTasks { tasks in
                guard let task = tasks.first(where: { $0.taskIdentifier == taskId }) else { return }
                task.cancel()
            }
        }

        for download in downloads {
            observable.on(.next(Update(download: download, kind: .cancelled)))
        }
    }

    func cancelAll() {
        DDLogInfo("AttachmentDownloader: stop all tasks")

        accessQueue.sync(flags: .barrier) { [weak self] in
            guard let self else { return }

            for download in activeDownloads.keys + queue.map({ $0.download }) {
                observable.on(.next(Update(download: download, kind: .cancelled)))
            }

            queue = []
            activeDownloads = [:]
            extractionObservers = [:]
            errors = [:]
            batchProgress = nil
            totalCount = 0
        }

        session?.getAllTasks { tasks in
            for task in tasks {
                task.cancel()
            }
        }

        dbQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.dbStorage.perform(request: DeleteAllDownloadsDbRequest(), on: self.dbQueue)
            } catch let error {
                DDLogError("AttachmentDownloader: can't delete all downloads - \(error)")
            }
        }
    }

    func data(for key: String, parentKey: String?, libraryId: LibraryIdentifier) -> (progress: CGFloat?, error: Swift.Error?) {
        return accessQueue.sync { [weak self] in
            guard let self else { return (nil, nil) }
            let download = Download(key: key, parentKey: parentKey, libraryId: libraryId)
            let error = errors[download]
            if let activeDownload = activeDownloads[download] {
                let progress = CGFloat(activeDownload.progress.fractionCompleted)
                return (progress, error)
            } else if queue.contains(where: { $0.download.key == key && $0.download.libraryId == libraryId }) {
                return (0, error)
            } else {
                return (nil, error)
            }
        }
    }

    private func resetBatchDataIfNeeded() {
        guard activeDownloads.isEmpty && queue.isEmpty else { return }
        batchProgress = nil
        totalCount = 0
    }

    // MARK: - Helpers

    private func addProgressToBatchProgress(progress: Progress) {
        if let batchProgress {
            batchProgress.addChild(progress, withPendingUnitCount: 100)
            batchProgress.totalUnitCount += 100
        } else {
            let batchProgress = Progress(totalUnitCount: 100)
            batchProgress.addChild(progress, withPendingUnitCount: 100)
            self.batchProgress = batchProgress
        }
        totalCount += 1
    }

    private func startNextDownloadIfPossible() {
        guard activeDownloads.count < Self.maxConcurrentDownloads && !queue.isEmpty else { return }

        let download = queue.removeFirst()

        if let task = createDownloadTask(from: download) {
            // Update local download with task id
            dbQueue.async { [weak self] in
                guard let self else { return }
                do {
                    let request = CreateEditDownloadDbRequest(
                        taskId: currentDownload.taskId,
                        key: currentDownload.download.key,
                        parentKey: currentDownload.download.parentKey,
                        libraryId: currentDownload.download.libraryId
                    )
                    try dbStorage.perform(request: request, on: dbQueue)
                } catch let error {
                    DDLogError("AttachmentDownloader: can't store newly created task id - \(error)")
                }
            }
            // Start download
            task.resume()
            return
        }

        dbQueue.async { [weak self] in
            guard let self else { return }
            do {
                try dbStorage.perform(request: DeleteDownloadDbRequest(key: download.download.key, libraryId: download.download.libraryId), on: dbQueue)
            } catch let error {
                DDLogError("AttachmentDownloader: could not remove unsuccessful task creation from db - \(error)")
            }
        }
        startNextDownloadIfPossible()

        func createDownloadTask(from enqueuedDownload: EnqueuedDownload) -> (URLSessionTask, Download, DownloadInProgress)? {
            do {
                let request: URLRequest
                if webDavController.sessionStorage.isEnabled {
                    guard let url = webDavController.currentUrl?.appendingPathComponent("\(enqueuedDownload.download.key).zip") else { return nil }
                    let apiRequest = FileRequest(webDavUrl: url, destination: enqueuedDownload.file)
                    request = try webDavController.createURLRequest(from: apiRequest)
                } else {
                    let apiRequest = FileRequest(libraryId: enqueuedDownload.download.libraryId, userId: userId, key: enqueuedDownload.download.key, destination: enqueuedDownload.file)
                    request = try apiClient.urlRequest(from: apiRequest)
                }
                let task = session!.downloadTask(with: request)

                let download = enqueuedDownload.download
                DDLogInfo("AttachmentDownloader: create download of \(download.key); (\(String(describing: download.parentKey))); \(download.libraryId) = \(task.taskIdentifier)")

                currentDownload = DownloadInProgress(
                    download: enqueuedDownload.download,
                    taskId: task.taskIdentifier,
                    file: enqueuedDownload.file,
                    progress: enqueuedDownload.progress,
                    extractAfterDownload: enqueuedDownload.extractAfterDownload,
                    logData: ApiLogger.log(urlRequest: request, encoding: .url, logParams: .headers)
                )
                return task
            } catch let error {
                errors[enqueuedDownload.download] = error
                observable.on(.next(.init(download: enqueuedDownload.download, kind: .failed(error))))
                return nil
            }
        }
    }

    private func finish(download: DownloadInProgress, result: Result<(), Swift.Error>, notifyObserver: Bool = true) {
        currentDownload = nil
        resetBatchDataIfNeeded()

        DDLogInfo("AttachmentDownloader: finished downloading \(download.taskId); \(download.download.key); (\(String(describing: download.download.parentKey))); \(download.download.libraryId)")

        dbQueue.sync { [weak self] in
            guard let self = self else { return }
            do {
                try dbStorage.perform(request: DeleteDownloadDbRequest(key: download.download.key, libraryId: download.download.libraryId), on: self.dbQueue)
            } catch let error {
                DDLogError("AttachmentDownloader: could not remove download from db - \(error)")
            }
        }

        switch result {
        case .success:
            errors[download.download] = nil
            if notifyObserver {
                observable.on(.next(Update(download: download.download, kind: .ready)))
            }

        case .failure(let error):
            if (error as NSError).code == NSURLErrorCancelled {
                errors[download.download] = nil
                batchProgress?.totalUnitCount -= 100
                if notifyObserver {
                    observable.on(.next(Update(download: download.download, kind: .cancelled)))
                }
            } else if fileStorage.has(download.file) {
                DDLogError("AttachmentDownloader: failed to download remotely changed attachment \(download.taskId) - \(error)")
                errors[download.download] = nil
                if notifyObserver {
                    observable.on(.next(Update(download: download.download, kind: .ready)))
                }
            } else {
                DDLogError("AttachmentDownloader: failed to download attachment \(download.taskId) - \(error)")
                errors[download.download] = error
                if notifyObserver {
                    observable.on(.next(Update(download: download.download, kind: .failed(error))))
                }
            }
        }

        if notifyObserver {
            // If observer notification is enabled, file is not being extracted and we can start downloading next file in queue
            startNextDownloadIfPossible()
        }
    }

    private func logResponse(for download: DownloadInProgress, task: URLSessionTask, error: Swift.Error?) {
        guard let data = download.logData else { return }
        let statusCode = (task.response as? HTTPURLResponse)?.statusCode ?? -1
        let headers = (task.response as? HTTPURLResponse)?.headers.dictionary
        if let error {
            ApiLogger.logFailedresponse(error: error, headers: headers, statusCode: statusCode, startData: data)
        } else {
            ApiLogger.logSuccessfulResponse(statusCode: statusCode, data: nil, headers: headers, startData: data)
        }
    }
}

extension AttachmentDownloader: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        var currentDownload: DownloadInProgress?
        accessQueue.sync { [weak self] in
            currentDownload = self?.currentDownload
        }
        guard let currentDownload else {
            DDLogError("AttachmentDownloader: didFinishDownloadingTo \(downloadTask.taskIdentifier) finished but currentDownload is nil")
            return
        }

        logResponse(for: currentDownload, task: downloadTask, error: nil)
        DDLogInfo("AttachmentDownloader: didFinishDownloadingTo \(downloadTask.taskIdentifier)")

        var zipFile: File?
        var shouldExtractAfterDownload = currentDownload.extractAfterDownload
        var isCompressed = webDavController.sessionStorage.isEnabled && !currentDownload.download.libraryId.isGroupLibrary
        if let response = downloadTask.response as? HTTPURLResponse {
            let _isCompressed = response.value(forHTTPHeaderField: "Zotero-File-Compressed") == "Yes"
            isCompressed = isCompressed || _isCompressed
        }
        if isCompressed {
            zipFile = currentDownload.file.copyWithExt("zip")
        } else {
            shouldExtractAfterDownload = false
        }

        do {
            if let error = checkFileResponse(for: Files.file(from: location)) {
                throw error
            }

            // If there is some older version of given file, remove so that it can be replaced
            if let zipFile, fileStorage.has(zipFile) {
                try fileStorage.remove(zipFile)
            }
            if fileStorage.has(currentDownload.file) {
                try fileStorage.remove(currentDownload.file)
            }
            // Move downloaded file to new location
            try fileStorage.move(from: location.path, to: zipFile ?? currentDownload.file)

            dbQueue.sync { [weak self] in
                guard let self else { return }
                // Mark file as downloaded in DB
                let request = MarkFileAsDownloadedDbRequest(key: currentDownload.download.key, libraryId: currentDownload.download.libraryId, downloaded: true, compressed: isCompressed)
                try? dbStorage.perform(request: request, on: dbQueue)
            }

            accessQueue.sync(flags: .barrier) { [weak self] in
                self?.finish(download: currentDownload, result: .success(()), notifyObserver: !shouldExtractAfterDownload)
            }

            if let zipFile, shouldExtractAfterDownload {
                extract(zipFile: zipFile, toFile: currentDownload.file, download: currentDownload.download)
            }
        } catch let error {
            accessQueue.sync(flags: .barrier) { [weak self] in
                self?.finish(download: currentDownload, result: .failure(error))
            }
        }

        func checkFileResponse(for file: File) -> Swift.Error? {
            let size = self.fileStorage.size(of: file)
            if size == 0 || (size == 9 && (try? self.fileStorage.read(file)).flatMap({ String(data: $0, encoding: .utf8) }) == "Not found") {
                try? self.fileStorage.remove(file)
                return AFError.responseValidationFailed(reason: .unacceptableStatusCode(code: 404))
            }
            return nil
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Swift.Error?) {
        accessQueue.sync(flags: .barrier) { [weak self] in
            guard let self, let error else { return }

            if let currentDownload {
                guard currentDownload.taskId == task.taskIdentifier else {
                    DDLogError("AttachmentDownloader: task finished with error for other than currentDownload")
                    return
                }
                logResponse(for: currentDownload, task: task, error: error)
                // Normally the `download` instance is available in `taskIdToDownload` and we can succesfully finish the download
                finish(download: currentDownload, result: .failure(error))
            } else {
                // Though in some cases the `URLSession` can report errors before `taskIdToDownload` is populated with data (when app was killed manually for example), so let's just store errors
                // so that it's apparent that these tasks finished already.
                initialErrors[task.taskIdentifier] = error
            }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        var currentDownload: DownloadInProgress?
        accessQueue.sync { [weak self] in
            currentDownload = self?.currentDownload
        }
        guard let currentDownload else { return }
        currentDownload.progress.completedUnitCount = Int64(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) * 100)
        observable.on(.next(Update(download: currentDownload.download, kind: .progress(CGFloat(currentDownload.progress.fractionCompleted)))))
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
