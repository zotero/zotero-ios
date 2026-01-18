//
//  RemoteAttachmentDownloader.swift
//  Zotero
//
//  Created by Michal Rentka on 19.05.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
@preconcurrency import RxSwift

/// Downloads attachments from Zotero's remote servers.
///
/// **Thread Safety (@unchecked Sendable - implicitly via accessQueue):**
/// All mutable state is protected by `accessQueue` (serial DispatchQueue):
/// - `downloads` - set of active downloads
/// - `operations` - dictionary of download operations
/// - `progressObservers` - dictionary of progress observers
/// - `errors` - dictionary of download errors
/// - `batchCount` and `totalBatchCount` - batch tracking
///
/// All mutations use `accessQueue.async(flags: .barrier)` for exclusive access.
/// Reads may use regular async or sync depending on requirements.
///
/// **RxSwift Integration:** Observable subjects are thread-safe by design.
final class RemoteAttachmentDownloader: @unchecked Sendable {
    struct Download: Hashable {
        let key: String
        let parentKey: String
        let libraryId: LibraryIdentifier
    }

    struct Update {
        enum Kind: Hashable {
            case progress(CGFloat)
            case ready(Attachment)
            case failed
            case cancelled
        }

        let download: Download
        let kind: Kind
    }

    private let accessQueue: DispatchQueue
    private let processingQueue: DispatchQueue
    private let operationQueue: OperationQueue
    private let disposeBag: DisposeBag
    private unowned let apiClient: ApiClient
    private unowned let fileStorage: FileStorage

    let observable: PublishSubject<Update>

    private var operations: [Download: RemoteAttachmentDownloadOperation]
    private var errors: [Download: Swift.Error]
    private var progressObservers: [Download: NSKeyValueObservation]
    private var batchProgress: Progress?
    private var totalBatchCount: Int = 0
    
    var batchData: (Progress?, Int, Int) {
        var progress: Progress?
        var totalBatchCount = 0
        var remainingBatchCount = 0

        self.accessQueue.sync { [weak self] in
            guard let self else { return }
            progress = self.batchProgress
            remainingBatchCount = self.operations.count
            totalBatchCount = self.totalBatchCount
        }

        return (progress, remainingBatchCount, totalBatchCount)
    }

    init(apiClient: ApiClient, fileStorage: FileStorage) {
        let processingQueue = DispatchQueue(label: "org.zotero.RemoteAttachmentDownloader.ProcessingQueue", qos: .userInteractive, attributes: .concurrent)
        let operationQueue = OperationQueue()
        operationQueue.maxConcurrentOperationCount = 2
        operationQueue.qualityOfService = .userInitiated
        operationQueue.underlyingQueue = processingQueue

        self.apiClient = apiClient
        self.fileStorage = fileStorage
        self.operationQueue = operationQueue
        self.accessQueue = DispatchQueue(label: "org.zotero.RemoteAttachmentDownloader.AccessQueue", qos: .userInteractive, attributes: .concurrent)
        self.processingQueue = processingQueue
        self.observable = PublishSubject()
        self.operations = [:]
        self.progressObservers = [:]
        self.errors = [:]
        self.disposeBag = DisposeBag()
    }

    func data(for key: String, parentKey: String, libraryId: LibraryIdentifier) -> (progress: CGFloat?, error: Swift.Error?) {
        let download = Download(key: key, parentKey: parentKey, libraryId: libraryId)
        var progress: CGFloat?
        var error: Swift.Error?

        self.accessQueue.sync { [weak self] in
            if let operation = self?.operations[download] {
                if let _progress = operation.progress {
                    progress = CGFloat(_progress.fractionCompleted)
                } else if operation.isExecuting || (operation.isReady && !operation.isCancelled) {
                    progress = 0
                }
            }
            error = self?.errors[download]
        }

        return (progress, error)
    }

    func download(data: [(Attachment, URL, String)]) {
        self.accessQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }

            DDLogInfo("RemoteAttachmentDownloader: enqueue \(data.count) attachments")

            let downloadAndOperations = data.compactMap({ createDownload(url: $0.1, attachment: $0.0, parentKey: $0.2) })
            let downloads = downloadAndOperations.map({ $0.0 })
            let operations = downloadAndOperations.map({ $0.1 })
            downloads.forEach {
                // Send first update to immediately reflect new state
                self.observable.on(.next(Update(download: $0, kind: .progress(0))))
            }
            operationQueue.addOperations(operations, waitUntilFinished: false)
        }
        
        func createDownload(url: URL, attachment: Attachment, parentKey: String) -> (Download, RemoteAttachmentDownloadOperation)? {
            let download = Download(key: attachment.key, parentKey: parentKey, libraryId: attachment.libraryId)

            guard operations[download] == nil, let file = attachment.file else { return nil }

            let progress = Progress(totalUnitCount: 100)
            let operation = RemoteAttachmentDownloadOperation(url: url, file: file, progress: progress, apiClient: apiClient, fileStorage: fileStorage, queue: processingQueue)
            
            // Capture self weakly to avoid retain cycles
            operation.finishedDownload = { [weak self] result in
                guard let self = self else { return }
                
                self.accessQueue.async(flags: .barrier) {
                    self.operations[download] = nil
                    self.progressObservers[download] = nil
                    self.resetBatchDataIfNeeded()

                    switch result {
                    case .success:
                        DDLogInfo("RemoteAttachmentDownloader: finished downloading \(download.key)")
                        self.observable.on(.next(Update(download: download, kind: .ready(attachment))))
                        self.errors[download] = nil

                    case .failure(let error):
                        DDLogError("RemoteAttachmentDownloader: failed to download attachment \(download.key), \(download.libraryId) - \(error)")

                        let isCancelError = (error as? RemoteAttachmentDownloadOperation.Error) == .cancelled
                        self.errors[download] = isCancelError ? nil : error

                        if isCancelError {
                            self.observable.on(.next(Update(download: download, kind: .cancelled)))
                        } else {
                            self.observable.on(.next(Update(download: download, kind: .failed)))
                        }
                    }
                }
            }
            
            operation.progressHandler = { [weak self] progress in
                guard let self = self else { return }
                
                self.accessQueue.async(flags: .barrier) {
                    let observer = progress.observe(\.fractionCompleted) { [weak self] progress, _ in
                        self?.observable.on(.next(Update(download: download, kind: .progress(CGFloat(progress.fractionCompleted)))))
                    }
                    self.progressObservers[download] = observer
                }
            }

            operations[download] = operation
            totalBatchCount += 1
            
            if let batchProgress {
                batchProgress.addChild(progress, withPendingUnitCount: 100)
                batchProgress.totalUnitCount += 100
            } else {
                let batchProgress = Progress(totalUnitCount: 100)
                batchProgress.addChild(progress, withPendingUnitCount: 100)
                self.batchProgress = batchProgress
            }

            return (download, operation)
        }
    }
    
    private func resetBatchDataIfNeeded() {
        guard operations.isEmpty else { return }
        totalBatchCount = 0
        batchProgress = nil
    }

    func stop() {
        DDLogInfo("RemoteAttachmentDownloader: stop")
        self.operationQueue.cancelAllOperations()
    }
}
