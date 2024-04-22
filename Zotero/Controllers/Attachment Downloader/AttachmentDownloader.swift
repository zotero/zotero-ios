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
            case progress
            case ready(compressed: Bool?)
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

    private struct ActiveDownload {
        let taskId: Int
        let file: File
        let progress: Progress
        let extractAfterDownload: Bool
        let logData: ApiLogger.StartData?
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
        session = URLSessionCreator.createSession(for: Self.sessionId, delegate: self, httpMaximumConnectionsPerHost: Self.maxConcurrentDownloads)
        session.getAllTasks { [weak self] tasks in
            guard let self else { return }
            resumeDownloads(tasks: tasks, downloader: self)
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

        func resumeDownloads(tasks: [URLSessionTask], downloader: AttachmentDownloader) {
            var taskIds: Set<Int> = []
            for task in tasks {
                taskIds.insert(task.taskIdentifier)
            }

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
                    guard let task = tasks.first(where: { $0.taskIdentifier == taskId }) else { continue }
                    task.cancel()
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

            func loadDatabaseDownloads(existingTaskIds: Set<Int>, dbStorage: DbStorage, dbQueue: DispatchQueue, fileStorage: FileStorage) -> (Set<Int>, [(Int, EnqueuedDownload)], [EnqueuedDownload]) {
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

            func storeDownloadData(for downloads: [(Int, EnqueuedDownload)], downloader: AttachmentDownloader) -> [(Download, Swift.Error)] {
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
                        logData: nil
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

    func cancelAll() {
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

    private func startNextDownloadIfPossible() {
        guard activeDownloads.count < Self.maxConcurrentDownloads && !queue.isEmpty else { return }

        let enqueuedDownload = queue.removeFirst()

        if let (task, download, activeDownload) = createDownloadTask(from: enqueuedDownload) {
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
                try dbStorage.perform(request: DeleteDownloadDbRequest(key: enqueuedDownload.download.key, libraryId: enqueuedDownload.download.libraryId), on: dbQueue)
            } catch let error {
                DDLogError("AttachmentDownloader: could not remove unsuccessful task creation from db - \(error)")
            }
        }
        startNextDownloadIfPossible()

        func createDownloadTask(from enqueuedDownload: EnqueuedDownload) -> (URLSessionTask, Download, ActiveDownload)? {
            do {
                let request: URLRequest
                if case .custom = enqueuedDownload.download.libraryId, webDavController.sessionStorage.isEnabled {
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

                let activeDownload = ActiveDownload(
                    taskId: task.taskIdentifier,
                    file: enqueuedDownload.file,
                    progress: enqueuedDownload.progress,
                    extractAfterDownload: enqueuedDownload.extractAfterDownload,
                    logData: ApiLogger.log(urlRequest: request, encoding: .url, logParams: .headers)
                )
                activeDownloads[download] = activeDownload
                taskIdToDownload[task.taskIdentifier] = download
                return (task, download, activeDownload)
            } catch let error {
                errors[enqueuedDownload.download] = error
                observable.on(.next(.init(download: enqueuedDownload.download, kind: .failed(error))))
                return nil
            }
        }
    }

    private func finish(activeDownload: ActiveDownload, download: Download, compressed: Bool?, result: Result<(Bool), Swift.Error>) {
        activeDownloads[download] = nil
        taskIdToDownload[activeDownload.taskId] = nil
        resetBatchDataIfNeeded()

        DDLogInfo("AttachmentDownloader: finished downloading \(activeDownload.taskId); \(download.key); \(download.parentKey ?? "-"); \(download.libraryId)")

        dbQueue.sync { [weak self] in
            guard let self else { return }
            do {
                try dbStorage.perform(request: DeleteDownloadDbRequest(key: download.key, libraryId: download.libraryId), on: dbQueue)
            } catch let error {
                DDLogError("AttachmentDownloader: could not remove download from db - \(error)")
            }
        }

        switch result {
        case .success(let notifyObserver):
            errors[download] = nil
            if notifyObserver {
                observable.on(.next(Update(download: download, kind: .ready(compressed: compressed))))
            }

        case .failure(let error):
            if (error as NSError).code == NSURLErrorCancelled {
                errors[download] = nil
                batchProgress?.totalUnitCount -= 100
                if totalCount > 0 {
                    totalCount -= 1
                }
                observable.on(.next(Update(download: download, kind: .cancelled)))
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

        if let data = activeDownload.logData {
            logResponse(for: data, task: downloadTask, error: nil)
        }
        DDLogInfo("AttachmentDownloader: didFinishDownloadingTo \(downloadTask.taskIdentifier)")

        var zipFile: File?
        var shouldExtractAfterDownload = activeDownload.extractAfterDownload
        var isCompressed = webDavController.sessionStorage.isEnabled && !download.libraryId.isGroupLibrary
        if let response = downloadTask.response as? HTTPURLResponse {
            let _isCompressed = response.value(forHTTPHeaderField: "Zotero-File-Compressed") == "Yes" || response.value(forHTTPHeaderField: "Content-Type") == "application/zip"
            isCompressed = isCompressed || _isCompressed
        }
        if isCompressed {
            zipFile = activeDownload.file.copyWithExt("zip")
        } else {
            shouldExtractAfterDownload = false
        }

        do {
            if let error = checkFileResponse(for: Files.file(from: location), fileStorage: fileStorage) {
                throw error
            }
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
                self?.finish(activeDownload: activeDownload, download: download, compressed: isCompressed, result: .success(!shouldExtractAfterDownload))
            }

            if let zipFile, shouldExtractAfterDownload {
                extract(zipFile: zipFile, toFile: activeDownload.file, download: download)
            }
        } catch let error {
            accessQueue.sync(flags: .barrier) { [weak self] in
                self?.finish(activeDownload: activeDownload, download: download, compressed: isCompressed, result: .failure(error))
            }
        }

        func checkFileResponse(for file: File, fileStorage: FileStorage) -> Swift.Error? {
            let size = fileStorage.size(of: file)
            if size == 0 || (size == 9 && (try? fileStorage.read(file)).flatMap({ String(data: $0, encoding: .utf8) })?.caseInsensitiveCompare("Not found") == .orderedSame) {
                try? fileStorage.remove(file)
                return AFError.responseValidationFailed(reason: .unacceptableStatusCode(code: 404))
            }
            return nil
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Swift.Error?) {
        accessQueue.sync(flags: .barrier) { [weak self] in
            guard let self, let error else { return }
            if let download = taskIdToDownload[task.taskIdentifier], let activeDownload = activeDownloads[download] {
                if let data = activeDownload.logData {
                    logResponse(for: data, task: task, error: error)
                }
                finish(activeDownload: activeDownload, download: download, compressed: nil, result: .failure(error))
            } else if activeDownloads.isEmpty {
                // Though in some cases the `URLSession` can report errors before `activeDownloads` is populated with data (when app was killed manually for example), so let's just store errors
                // so that it's apparent that these tasks finished already.
                initialErrors[task.taskIdentifier] = error
            }
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
