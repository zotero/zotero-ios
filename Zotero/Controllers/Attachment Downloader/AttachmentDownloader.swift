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
        case cancelled
    }

    struct Update {
        enum Kind {
            case progress
            case ready(compressed: Bool?)
            case failed(Swift.Error)
            case cancelled

            var isProgress: Bool {
                switch self {
                case .progress:
                    return true

                case .ready, .failed, .cancelled:
                    return false
                }
            }
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

    private struct ActiveDownload {
        let taskId: Int
        let file: File
        let progress: Progress
        let extractAfterDownload: Bool
        let logData: ApiLogger.StartData?
        let attempt: Int
    }

    private struct Extraction {
        let progress: Progress
        let observer: NSKeyValueObservation
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
    private var activeDownloads: [Download: ActiveDownload]
    private var taskIdToDownload: [Int: Download]
    private var extractions: [Download: Extraction]
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
            guard let self else { return }
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
        activeDownloads = [:]
        taskIdToDownload = [:]
        extractions = [:]
        totalCount = 0
        errors = [:]
        initialErrors = [:]
        accessQueue = DispatchQueue(label: "org.zotero.AttachmentDownloader.AccessQueue", qos: .userInteractive, attributes: .concurrent)
        dbQueue = DispatchQueue(label: "org.zotero.AttachmentDownloader.DbQueue", qos: .userInteractive)
        unzipQueue = DispatchQueue(label: "org.zotero.AttachmentDownloader.UnzipQueue", qos: .userInteractive, attributes: .concurrent)
        observable = PublishSubject()
        disposeBag = DisposeBag()

        super.init()

        #if TESTING
        let configuration = URLSessionConfiguration.default
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        #else
        session = URLSessionCreator.createSession(
            for: Self.sessionId,
            forwardingDelegate: self,
            forwardingTaskDelegate: self,
            forwardingDownloadDelegate: self,
            httpMaximumConnectionsPerHost: Self.maxConcurrentDownloads
        )
        session.getAllTasks { [weak self] tasks in
            guard let self else { return }
            let tasksGroupedByIdentifier = Dictionary(grouping: tasks, by: { $0.taskIdentifier })
            resumeDownloads(tasksGroupedByIdentifier: tasksGroupedByIdentifier, downloader: self)
        }
        #endif

        NotificationCenter.default
            .rx
            .notification(.attachmentFileDeleted)
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] notification in
                guard let self, let notification = notification.object as? AttachmentFileDeletedNotification else { return }
                handleDeletedAttachments(notification: notification, downloader: self)
            })
            .disposed(by: disposeBag)

        func resumeDownloads(tasksGroupedByIdentifier: [Int: [URLSessionTask]], downloader: AttachmentDownloader) {
            let taskIds = Set(tasksGroupedByIdentifier.keys)
            downloader.dbQueue.async { [weak downloader] in
                guard let downloader else { return }
                let (cancelledTaskIds, activeDownloads, downloadsToRestore) = loadDatabaseDownloads(
                    existingTaskIds: taskIds,
                    dbStorage: downloader.dbStorage,
                    dbQueue: downloader.dbQueue,
                    fileStorage: downloader.fileStorage
                )

                DDLogInfo("AttachmentDownloader: cancel stored downloads - \(cancelledTaskIds.count)")
                for taskId in cancelledTaskIds {
                    tasksGroupedByIdentifier[taskId]?.forEach { $0.cancel() }
                }

                guard !activeDownloads.isEmpty || !downloadsToRestore.isEmpty else { return }

                downloader.accessQueue.async(flags: .barrier) { [weak downloader] in
                    guard let downloader else { return }

                    DDLogInfo("AttachmentDownloader: cache downloads in progress - \(activeDownloads.count); restore downloads - \(downloadsToRestore.count)")

                    let failedDownloads = storeDownloadData(for: activeDownloads, downloader: downloader)
                    downloader.queue = downloadsToRestore

                    for download in activeDownloads {
                        if let (download, error) = failedDownloads.first(where: { $0.0 == download.1.download }) {
                            downloader.observable.on(.next(Update(download: download, kind: .failed(error))))
                        } else {
                            downloader.observable.on(.next(Update(download: download.1.download, kind: .progress)))
                        }
                    }
                    for download in downloadsToRestore {
                        downloader.addProgressToBatchProgress(progress: download.progress)
                        downloader.observable.on(.next(Update(download: download.download, kind: .progress)))
                    }

                    downloader.startNextDownloadIfPossible()

                    guard !failedDownloads.isEmpty else { return }

                    downloader.dbQueue.async { [weak downloader] in
                        guard let downloader else { return }
                        do {
                            let requests = failedDownloads.map({ DeleteDownloadDbRequest(key: $0.0.key, libraryId: $0.0.libraryId) })
                            try downloader.dbStorage.perform(writeRequests: requests, on: downloader.dbQueue)
                        } catch let error {
                            DDLogError("AttachmentDownloader: can't update downloads - \(error)")
                        }
                    }
                }
            }

            @Sendable func loadDatabaseDownloads(existingTaskIds: Set<Int>, dbStorage: DbStorage, dbQueue: DispatchQueue, fileStorage: FileStorage) -> (Set<Int>, [(Int, EnqueuedDownload)], [EnqueuedDownload]) {
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
                              let file = attachment.file
                        else {
                            // Attachment item doesn't exist anymore, cancel download
                            toDelete.append(download)
                            if let taskId = rDownload.taskId {
                                cancelledTaskIds.insert(taskId)
                            }
                            continue
                        }

                        let enqueuedDownload = EnqueuedDownload(download: download, file: file, progress: Progress(), extractAfterDownload: false)
                        if let taskId = rDownload.taskId, existingTaskIds.contains(taskId) {
                            // Download is ongoing, cache data
                            activeDownloads.append((taskId, enqueuedDownload))
                        } else {
                            // Download was cancelled by OS, restart download
                            downloadsToRestore.append(enqueuedDownload)
                        }
                    }

                    let requests = toDelete.map({ DeleteDownloadDbRequest(key: $0.key, libraryId: $0.libraryId) })
                    try dbStorage.perform(writeRequests: requests, on: dbQueue)
                } catch let error {
                    DDLogError("AttachmentDownloader: can't load downloads - \(error)")
                }

                return (cancelledTaskIds, activeDownloads, downloadsToRestore)
            }

            @Sendable func storeDownloadData(for downloads: [(Int, EnqueuedDownload)], downloader: AttachmentDownloader) -> [(Download, Swift.Error)] {
                var failed: [(Download, Swift.Error)] = []
                for (taskId, enqueuedDownload) in downloads {
                    DDLogInfo("AttachmentDownloader: cached \(taskId); \(enqueuedDownload.download.key); (\(enqueuedDownload.download.parentKey ?? "-")); \(enqueuedDownload.download.libraryId)")
                    let progress = Progress(totalUnitCount: 100)
                    downloader.addProgressToBatchProgress(progress: progress)
                    if let error = downloader.initialErrors[taskId] {
                        downloader.errors[enqueuedDownload.download] = error
                        progress.completedUnitCount = 100
                        failed.append((enqueuedDownload.download, error))
                        continue
                    }
                    downloader.activeDownloads[enqueuedDownload.download] = ActiveDownload(
                        taskId: taskId,
                        file: enqueuedDownload.file,
                        progress: progress,
                        extractAfterDownload: false,
                        logData: nil,
                        attempt: 0
                    )
                    downloader.taskIdToDownload[taskId] = enqueuedDownload.download
                }
                return failed
            }
        }

        func handleDeletedAttachments(notification: AttachmentFileDeletedNotification, downloader: AttachmentDownloader) {
            switch notification {
            case .individual(let key, let parentKey, let libraryId):
                downloader.cancel(key: key, parentKey: parentKey, libraryId: libraryId)

            case .allForItems(let keys, let libraryId):
                downloader.dbQueue.async { [weak downloader] in
                    guard let downloader else { return }
                    do {
                        let downloads = try downloader.dbStorage.perform(request: DeleteDownloadsDbRequest(keys: keys, libraryId: libraryId), on: downloader.dbQueue)
                        downloader.cancel(downloads: downloads)
                    } catch let error {
                        DDLogError("AttachmentDownloader: can't delete downloads for \(keys); \(libraryId) - \(error)")
                    }
                }

            case .library(let libraryId):
                downloader.dbQueue.async { [weak downloader] in
                    guard let downloader else { return }
                    do {
                        let downloads = try downloader.dbStorage.perform(request: DeleteLibraryDownloadsDbRequest(libraryId: libraryId), on: downloader.dbQueue)
                        downloader.cancel(downloads: downloads)
                    } catch let error {
                        DDLogError("AttachmentDownloader: can't delete downloads for \(libraryId) - \(error)")
                    }
                }

            case .all:
                downloader.cancelAll()
            }
        }
    }

    // MARK: - Actions

    func handleEventsForBackgroundURLSession(with identifier: String, completionHandler: @escaping () -> Void) -> Bool {
        guard identifier == Self.sessionId else { return false }
        DDLogInfo("AttachmentDownloader: handle events for background url session \(identifier)")
        backgroundCompletionHandler = completionHandler
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
                    case .linkedFile:
                        break

                    case .importedFile, .importedUrl, .embeddedImage:
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
            for download in downloads {
                observable.on(.next(Update(download: download.download, kind: .progress)))
            }
            startNextDownloadIfPossible()
        }
    }

    func downloadIfNeeded(attachment: Attachment, parentKey: String?) {
        switch attachment.type {
        case .url:
            DDLogInfo("AttachmentDownloader: open url \(attachment.key)")
            observable.on(.next(Update(key: attachment.key, parentKey: parentKey, libraryId: attachment.libraryId, kind: .ready(compressed: nil))))

        case .file(let filename, let contentType, let location, let linkType, let compressed):
            switch linkType {
            case .linkedFile:
                DDLogWarn("AttachmentDownloader: tried opening linkedFile or embeddedImage \(attachment.key)")
                observable.on(.next(Update(key: attachment.key, parentKey: parentKey, libraryId: attachment.libraryId, kind: .failed(Error.incompatibleAttachment))))

            case .importedFile, .importedUrl, .embeddedImage:
                switch location {
                case .local:
                    if compressed {
                        let file = Files.attachmentFile(in: attachment.libraryId, key: attachment.key, filename: filename, contentType: contentType)
                        extract(zipFile: file.copy(withExt: "zip"), toFile: file, download: Download(key: attachment.key, parentKey: parentKey, libraryId: attachment.libraryId))
                    } else {
                        DDLogInfo("AttachmentDownloader: open local file \(attachment.key)")
                        observable.on(.next(Update(key: attachment.key, parentKey: parentKey, libraryId: attachment.libraryId, kind: .ready(compressed: false))))
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
            dbQueue.async { [weak self] in
                guard let self else { return }
                do {
                    let request = CreateEditDownloadDbRequest(taskId: nil, key: key, parentKey: parentKey, libraryId: libraryId)
                    try dbStorage.perform(request: request, on: dbQueue)
                } catch let error {
                    DDLogError("AttachmentDownloader: couldn't store download to db - \(error)")
                }
            }

            accessQueue.async(flags: .barrier) { [weak self] in
                guard let self else { return }

                DDLogInfo("AttachmentDownloader: enqueue \(key)")

                let progress = Progress(totalUnitCount: 100)
                addProgressToBatchProgress(progress: progress)
                let download = EnqueuedDownload(download: Download(key: key, parentKey: parentKey, libraryId: libraryId), file: file, progress: progress, extractAfterDownload: true)
                queue.insert(download, at: 0)
                observable.on(.next(Update(download: download.download, kind: .progress)))
                startNextDownloadIfPossible()
            }
        }
    }

    func downloadIfNeeded(attachment: Attachment, parentKey: String?, scheduler: SchedulerType = MainScheduler.instance, completion: @escaping (Result<(), Swift.Error>) -> Void) {
        observable
            .observe(on: scheduler)
            .filter { update in
                guard update.libraryId == attachment.libraryId && update.key == attachment.key else { return false }
                switch update.kind {
                case .cancelled, .failed, .ready:
                    return true

                case .progress:
                    return false
                }
            }
            .first()
            .subscribe { update in
                guard let update else { return }
                switch update.kind {
                case .ready:
                    completion(.success(()))

                case .cancelled:
                    completion(.failure(Error.cancelled))

                case .failed(let error):
                    completion(.failure(error))

                case .progress:
                    break
                }
            }
            .disposed(by: disposeBag)

        downloadIfNeeded(attachment: attachment, parentKey: parentKey)
    }

    private func extract(zipFile: File, toFile file: File, download: Download) {
        unzipQueue.async { [weak self] in
            guard let self else { return }
            do {
                // Check whether zip file exists
                if !fileStorage.has(zipFile) {
                    // Check whether file exists
                    if !fileStorage.has(file) {
                        throw AttachmentDownloader.Error.cantUnzipSnapshot
                    }

                    // Try removing zip file, don't return error if it fails, we've got what we wanted.
                    try? fileStorage.remove(zipFile)
                    finishExtraction(downloader: self)
                    return
                }
                // Remove other contents of folder so that zip extraction doesn't fail
                let files: [File] = try fileStorage.contentsOfDirectory(at: zipFile.directory)
                for file in files {
                    guard file.name != zipFile.name || file.ext != zipFile.ext else { continue }
                    try? fileStorage.remove(file)
                }
                let progress = Progress(totalUnitCount: 100)
                let observer = progress.observe(\.fractionCompleted) { [weak self] progress, _ in
                    guard let self else { return }
                    let completedCount = progress.completedUnitCount
                    accessQueue.sync { [weak self] in
                        self?.extractions[download]?.progress.completedUnitCount = completedCount
                    }
                    observable.on(.next(Update(download: download, kind: .progress)))
                }
                accessQueue.sync(flags: .barrier) { [weak self] in
                    self?.extractions[download] = Extraction(progress: progress, observer: observer)
                }
                // Send first progress update
                observable.on(.next(Update(download: download, kind: .progress)))
                // Unzip to same directory
                try FileManager.default.unzipItem(at: zipFile.createUrl(), to: zipFile.createRelativeUrl(), progress: progress)
                // Try removing zip file, don't return error if it fails, we've got what we wanted.
                try? fileStorage.remove(zipFile)
                // Rename unzipped file if zip contained only 1 file and the names don't match
                let unzippedFiles: [File] = try fileStorage.contentsOfDirectory(at: file.directory)
                if unzippedFiles.count == 1, let unzipped = unzippedFiles.first, (unzipped.name != file.name) || (unzipped.ext != file.ext) {
                    try? fileStorage.move(from: unzipped, to: file)
                }
                // Check whether file exists
                if !fileStorage.has(file) {
                    throw AttachmentDownloader.Error.zipDidntContainRequestedFile
                }
                finishExtraction(downloader: self)
            } catch let error {
                DDLogError("AttachmentDownloader: unzip error - \(error)")
                if let error = error as? AttachmentDownloader.Error {
                    report(error: error, downloader: self)
                } else {
                    report(error: AttachmentDownloader.Error.cantUnzipSnapshot, downloader: self)
                }
            }
        }

        func finishExtraction(downloader: AttachmentDownloader) {
            self.dbQueue.async { [weak downloader] in
                guard let downloader else { return }
                do {
                    let request = MarkFileAsDownloadedDbRequest(key: download.key, libraryId: download.libraryId, downloaded: true, compressed: false)
                    try downloader.dbStorage.perform(request: request, on: downloader.dbQueue)
                    downloader.accessQueue.async(flags: .barrier) { [weak downloader] in
                        guard let downloader else { return }
                        downloader.extractions[download] = nil
                        downloader.observable.on(.next(Update(download: download, kind: .ready(compressed: false))))
                    }
                } catch let error {
                    DDLogError("AttachmentDownloader: can't store new compressed value - \(error)")
                    report(error: AttachmentDownloader.Error.cantUnzipSnapshot, downloader: downloader)
                }
            }
        }

        func report(error: Error, downloader: AttachmentDownloader) {
            downloader.accessQueue.async(flags: .barrier) { [weak downloader] in
                guard let downloader else { return }
                downloader.errors[download] = error
                downloader.extractions[download] = nil
                downloader.observable.on(.next(Update(download: download, kind: .failed(error))))
            }
        }
    }

    func cancel(key: String, parentKey: String?, libraryId: LibraryIdentifier) {
        let download = Download(key: key, parentKey: parentKey, libraryId: libraryId)
        cancel(downloads: [download])

        dbQueue.async { [weak self] in
            guard let self else { return }
            do {
                try dbStorage.perform(request: DeleteDownloadDbRequest(key: key, libraryId: libraryId), on: dbQueue)
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
                    taskIdToDownload[activeDownload.taskId] = nil
                    extractions[download] = nil
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

    func cancelAll(invalidateSession: Bool = false) {
        DDLogInfo("AttachmentDownloader: stop all tasks")

        accessQueue.sync(flags: .barrier) { [weak self] in
            guard let self else { return }

            for download in activeDownloads.keys + queue.map({ $0.download }) {
                observable.on(.next(Update(download: download, kind: .cancelled)))
            }

            queue = []
            activeDownloads = [:]
            taskIdToDownload = [:]
            extractions = [:]
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
                try dbStorage.perform(request: DeleteAllDownloadsDbRequest(), on: dbQueue)
            } catch let error {
                DDLogError("AttachmentDownloader: can't delete all downloads - \(error)")
            }
        }

        if invalidateSession {
            session?.invalidateAndCancel()
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
            } else if let extraction = extractions[download] {
                let progress = CGFloat(extraction.progress.fractionCompleted)
                return (progress, nil)
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
            batchProgress.addChild(progress, withPendingUnitCount: progress.totalUnitCount)
            batchProgress.totalUnitCount += progress.totalUnitCount
        } else {
            let batchProgress = Progress(totalUnitCount: progress.totalUnitCount)
            batchProgress.addChild(progress, withPendingUnitCount: progress.totalUnitCount)
            self.batchProgress = batchProgress
        }
        totalCount += 1
    }

    private func createDownloadTask(for download: Download, file: File, progress: Progress, extractAfterDownload: Bool, attempt: Int) -> (URLSessionTask, ActiveDownload)? {
        do {
            let request: URLRequest
            if case .custom = download.libraryId, webDavController.sessionStorage.isEnabled {
                guard let url = webDavController.currentUrl?.appendingPathComponent("\(download.key).zip") else { return nil }
                let apiRequest = FileRequest(webDavUrl: url, destination: file)
                request = try webDavController.createURLRequest(from: apiRequest)
            } else {
                let apiRequest = FileRequest(libraryId: download.libraryId, userId: userId, key: download.key, destination: file)
                request = try apiClient.urlRequest(from: apiRequest)
            }
            let task = session!.downloadTask(with: request)

            DDLogInfo("AttachmentDownloader: create download of \(download.key); (\(String(describing: download.parentKey))); \(download.libraryId) = \(task.taskIdentifier)")

            let activeDownload = ActiveDownload(
                taskId: task.taskIdentifier,
                file: file,
                progress: progress,
                extractAfterDownload: extractAfterDownload,
                logData: ApiLogger.log(urlRequest: request, encoding: .url, logParams: .headers),
                attempt: attempt
            )
            activeDownloads[download] = activeDownload
            taskIdToDownload[task.taskIdentifier] = download
            return (task, activeDownload)
        } catch let error {
            errors[download] = error
            observable.on(.next(.init(download: download, kind: .failed(error))))
            return nil
        }
    }

    private func createDownloadTask(from enqueuedDownload: EnqueuedDownload) -> (URLSessionTask, ActiveDownload)? {
        createDownloadTask(for: enqueuedDownload.download, file: enqueuedDownload.file, progress: enqueuedDownload.progress, extractAfterDownload: enqueuedDownload.extractAfterDownload, attempt: 0)
    }

    private func createDownloadTask(from download: Download, retrying activeDownload: ActiveDownload) -> (URLSessionTask, ActiveDownload)? {
        createDownloadTask(for: download, file: activeDownload.file, progress: activeDownload.progress, extractAfterDownload: activeDownload.extractAfterDownload, attempt: activeDownload.attempt + 1)
    }

    private func startDownloadTask(for download: Download, downloadTaskTuple: (URLSessionTask, ActiveDownload)?) {
        if let (task, activeDownload) = downloadTaskTuple {
            // Update local download with task id
            dbQueue.async { [weak self] in
                guard let self else { return }
                do {
                    let request = CreateEditDownloadDbRequest(
                        taskId: activeDownload.taskId,
                        key: download.key,
                        parentKey: download.parentKey,
                        libraryId: download.libraryId
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
                try dbStorage.perform(request: DeleteDownloadDbRequest(key: download.key, libraryId: download.libraryId), on: dbQueue)
            } catch let error {
                DDLogError("AttachmentDownloader: could not remove unsuccessful task creation from db - \(error)")
            }
        }
        startNextDownloadIfPossible()
    }

    private func startNextDownloadIfPossible() {
        guard activeDownloads.count < Self.maxConcurrentDownloads && !queue.isEmpty else { return }

        let enqueuedDownload = queue.removeFirst()
        startDownloadTask(for: enqueuedDownload.download, downloadTaskTuple: createDownloadTask(from: enqueuedDownload))
    }

    private func retryDownload(_ download: Download, after activeDownload: ActiveDownload) {
        startDownloadTask(for: download, downloadTaskTuple: createDownloadTask(from: download, retrying: activeDownload))
    }

    private static let maxAttemptCount = 10

    private func finish(activeDownload: ActiveDownload, download: Download, compressed: Bool?, result: Result<Bool, Swift.Error>, retryDelay: RetryDelay?) {
        activeDownloads[download] = nil
        taskIdToDownload[activeDownload.taskId] = nil
        resetBatchDataIfNeeded()

        DDLogInfo("AttachmentDownloader: finished downloading \(activeDownload.taskId); \(download.key); \(download.parentKey ?? "-"); \(download.libraryId)")

        switch result {
        case .success(let notifyObserver):
            deleteDownload()
            errors[download] = nil
            if notifyObserver {
                observable.on(.next(Update(download: download, kind: .ready(compressed: compressed))))
            }

        case .failure(let error):
            if (error as NSError).code == NSURLErrorCancelled {
                deleteDownload()
                errors[download] = nil
                batchProgress?.totalUnitCount -= 100
                if totalCount > 0 {
                    totalCount -= 1
                }
                observable.on(.next(Update(download: download, kind: .cancelled)))
            } else if let retryDelay, activeDownload.attempt + 1 < Self.maxAttemptCount {
                // File should be removed by caller, no need to remove it here.
                let nextAttempt = activeDownload.attempt + 1
                DDLogInfo("AttachmentDownloader: retrying download of \(download.key); \(download.parentKey ?? "-"); \(download.libraryId)")
                accessQueue.asyncAfter(deadline: .now() + retryDelay.seconds(for: nextAttempt)) { [weak self] in
                    self?.retryDownload(download, after: activeDownload)
                }
                return
            } else if fileStorage.has(activeDownload.file) {
                DDLogError("AttachmentDownloader: failed to download remotely changed attachment \(activeDownload.taskId) - \(error)")
                errors[download] = nil
                observable.on(.next(Update(download: download, kind: .ready(compressed: compressed))))
            } else {
                DDLogError("AttachmentDownloader: failed to download attachment \(activeDownload.taskId) - \(error)")
                errors[download] = error
                observable.on(.next(Update(download: download, kind: .failed(error))))
            }
        }

        // If observer notification is enabled, file is not being extracted and we can start downloading next file in queue
        startNextDownloadIfPossible()

        func deleteDownload() {
            dbQueue.sync { [weak self] in
                guard let self else { return }
                do {
                    try dbStorage.perform(request: DeleteDownloadDbRequest(key: download.key, libraryId: download.libraryId), on: dbQueue)
                } catch let error {
                    DDLogError("AttachmentDownloader: could not remove download from db - \(error)")
                }
            }
        }
    }

    private func logResponse(for startData: ApiLogger.StartData, task: URLSessionTask, error: Swift.Error?) {
        let statusCode = (task.response as? HTTPURLResponse)?.statusCode ?? -1
        let headers = (task.response as? HTTPURLResponse)?.headers.dictionary
        if let error {
            ApiLogger.logFailedresponse(error: error, headers: headers, statusCode: statusCode, startData: startData)
        } else {
            ApiLogger.logSuccessfulResponse(statusCode: statusCode, data: nil, headers: headers, startData: startData)
        }
    }
}

extension AttachmentDownloader: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let statusCode = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? -1
        var download: Download?
        var activeDownload: ActiveDownload?
        accessQueue.sync { [weak self] in
            guard let self else { return }
            download = taskIdToDownload[downloadTask.taskIdentifier]
            activeDownload = download.flatMap({ self.activeDownloads[$0] })
        }
        guard let download, let activeDownload else {
            DDLogError("AttachmentDownloader: didFinishDownloadingTo \(downloadTask.taskIdentifier) finished but currentDownload is nil")
            return
        }

        let error: Swift.Error?
        var retryDelay: RetryDelay?
        switch statusCode {
        case 401:
            error = createError(from: downloadTask, statusCode: 401, response: "Unauthorized")

        case 403:
            error = createError(from: downloadTask, statusCode: 403, response: "Forbidden")

        case 404:
            error = createError(from: downloadTask, statusCode: 404, response: "Not Found")

        case 429:
            error = createError(from: downloadTask, statusCode: 429, response: "Too Many Requests")
            if let response = downloadTask.response as? HTTPURLResponse, let retryAfter = response.value(forHTTPHeaderField: "Retry-After") {
                if let interval = TimeInterval(retryAfter) {
                    retryDelay = .constant(interval)
                } else if let retryDate = DateFormatter().date(from: retryAfter) {
                    retryDelay = .constant(retryDate.timeIntervalSinceNow)
                } else {
                    retryDelay = .progressive()
                }
            }

        default:
            error = checkFileResponse(for: Files.file(from: location), fileStorage: fileStorage, downloadTask: downloadTask)
        }
        if let data = activeDownload.logData {
            logResponse(for: data, task: downloadTask, error: error)
        }
        DDLogInfo("AttachmentDownloader: didFinishDownloadingTo \(downloadTask.taskIdentifier)")

        if let error {
            try? fileStorage.remove(Files.file(from: location))
            accessQueue.sync(flags: .barrier) { [weak self] in
                self?.finish(activeDownload: activeDownload, download: download, compressed: nil, result: .failure(error), retryDelay: retryDelay)
            }
            return
        }

        var zipFile: File?
        var shouldExtractAfterDownload = activeDownload.extractAfterDownload
        var isCompressed = webDavController.sessionStorage.isEnabled && !download.libraryId.isGroupLibrary
        if let response = downloadTask.response as? HTTPURLResponse {
            let _isCompressed = response.value(forHTTPHeaderField: "Content-Type") == "application/zip"
            isCompressed = isCompressed || _isCompressed
        }
        if isCompressed {
            zipFile = activeDownload.file.copy(withExt: "zip")
        } else {
            shouldExtractAfterDownload = false
        }

        do {
            // If there is some older version of given file, remove so that it can be replaced
            if let zipFile, fileStorage.has(zipFile) {
                try fileStorage.remove(zipFile)
            }
            if fileStorage.has(activeDownload.file) {
                try fileStorage.remove(activeDownload.file)
            }
            // Move downloaded file to new location
            try fileStorage.move(from: location.path, to: zipFile ?? activeDownload.file)

            dbQueue.sync { [weak self] in
                guard let self else { return }
                // Mark file as downloaded in DB
                let request = MarkFileAsDownloadedDbRequest(key: download.key, libraryId: download.libraryId, downloaded: true, compressed: isCompressed)
                try? dbStorage.perform(request: request, on: dbQueue)
            }

            accessQueue.sync(flags: .barrier) { [weak self] in
                self?.finish(activeDownload: activeDownload, download: download, compressed: isCompressed, result: .success(!shouldExtractAfterDownload), retryDelay: nil)
            }

            if let zipFile, shouldExtractAfterDownload {
                extract(zipFile: zipFile, toFile: activeDownload.file, download: download)
            }
        } catch let error {
            accessQueue.sync(flags: .barrier) { [weak self] in
                self?.finish(activeDownload: activeDownload, download: download, compressed: isCompressed, result: .failure(error), retryDelay: nil)
            }
        }

        func checkFileResponse(for file: File, fileStorage: FileStorage, downloadTask: URLSessionDownloadTask) -> Swift.Error? {
            if fileStorage.isEmptyOrNotFoundResponse(file: file) {
                return createError(from: downloadTask, statusCode: 404, response: "Not Found")
            }
            return nil
        }

        func createError(from downloadTask: URLSessionDownloadTask, statusCode: Int, response: String) -> AFResponseError {
            return AFResponseError(
                url: downloadTask.currentRequest?.url,
                httpMethod: downloadTask.currentRequest?.httpMethod ?? "Unknown",
                error: .responseValidationFailed(reason: .unacceptableStatusCode(code: statusCode)),
                headers: (downloadTask.response as? HTTPURLResponse)?.allHeaderFields,
                response: response
            )
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        var download: Download?
        var activeDownload: ActiveDownload?
        accessQueue.sync { [weak self] in
            guard let self else { return }
            download = taskIdToDownload[downloadTask.taskIdentifier]
            activeDownload = download.flatMap({ self.activeDownloads[$0] })
        }
        guard let download, let activeDownload else { return }
        activeDownload.progress.completedUnitCount = Int64(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) * 100)
        observable.on(.next(Update(download: download, kind: .progress)))
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

extension AttachmentDownloader: URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let sessionStorage = webDavController.sessionStorage
        let protectionSpace = challenge.protectionSpace
        guard sessionStorage.isEnabled,
              sessionStorage.isVerified,
              protectionSpace.authenticationMethod == NSURLAuthenticationMethodHTTPBasic || protectionSpace.authenticationMethod == NSURLAuthenticationMethodHTTPDigest,
              protectionSpace.host == sessionStorage.host,
              protectionSpace.port == sessionStorage.port,
              protectionSpace.protocol == sessionStorage.scheme.rawValue
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(user: sessionStorage.username, password: sessionStorage.password, persistence: .permanent))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Swift.Error?) {
        accessQueue.sync(flags: .barrier) { [weak self] in
            guard let self, let error else { return }
            if let download = taskIdToDownload[task.taskIdentifier], let activeDownload = activeDownloads[download] {
                if let data = activeDownload.logData {
                    logResponse(for: data, task: task, error: error)
                }
                finish(activeDownload: activeDownload, download: download, compressed: nil, result: .failure(error), retryDelay: nil)
            } else if activeDownloads.isEmpty {
                // Though in some cases the `URLSession` can report errors before `activeDownloads` is populated with data (when app was killed manually for example), so let's just store errors
                // so that it's apparent that these tasks finished already.
                initialErrors[task.taskIdentifier] = error
            }
        }
    }
}
