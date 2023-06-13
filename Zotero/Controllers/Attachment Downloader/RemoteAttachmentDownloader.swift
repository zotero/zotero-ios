//
//  RemoteAttachmentDownloader.swift
//  Zotero
//
//  Created by Michal Rentka on 19.05.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxSwift

final class RemoteAttachmentDownloader {
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

    private let queue: DispatchQueue
    private let operationQueue: OperationQueue
    private let disposeBag: DisposeBag
    private unowned let apiClient: ApiClient
    private unowned let fileStorage: FileStorage

    let observable: PublishSubject<Update>

    private var operations: [Download: RemoteAttachmentDownloadOperation]
    private var errors: [Download: Swift.Error]
    private var progressObservers: [Download: NSKeyValueObservation]

    init(apiClient: ApiClient, fileStorage: FileStorage) {
        let queue = DispatchQueue(label: "org.zotero.RemoteAttachmentDownloader.ProcessingQueue", qos: .userInteractive, attributes: .concurrent)
        let operationQueue = OperationQueue()
        operationQueue.maxConcurrentOperationCount = 2
        operationQueue.qualityOfService = .userInitiated
        operationQueue.underlyingQueue = queue

        self.apiClient = apiClient
        self.fileStorage = fileStorage
        self.operationQueue = operationQueue
        self.queue = queue
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

        self.queue.sync { [weak self] in
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
        self.queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            DDLogInfo("RemoteAttachmentDownloader: enqueue \(data.count) attachments")

            let operations = data.compactMap({ self.createDownload(url: $0.1, attachment: $0.0, parentKey: $0.2) })
            self.operationQueue.addOperations(operations, waitUntilFinished: false)
        }
    }

    private func createDownload(url: URL, attachment: Attachment, parentKey: String) -> RemoteAttachmentDownloadOperation? {
        let download = Download(key: attachment.key, parentKey: parentKey, libraryId: attachment.libraryId)

        guard self.operations[download] == nil, let file = self.file(for: attachment) else { return nil }

        let operation = RemoteAttachmentDownloadOperation(url: url, file: file, apiClient: self.apiClient, fileStorage: self.fileStorage, queue: self.queue)
        operation.finishedDownload = { [weak self] result in
            self?.queue.async(flags: .barrier) {
                guard let self = self else { return }
                self.finish(download: download, file: file, attachment: attachment, parentKey: parentKey, result: result)
            }
        }
        operation.progressHandler = { [weak self] progress in
            self?.queue.async(flags: .barrier) {
                guard let self = self else { return }
                self.observe(progress: progress, attachment: attachment, download: download)
            }
        }

        self.operations[download] = operation

        return operation
    }

    private func observe(progress: Progress, attachment: Attachment, download: Download) {
        let observer = progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            self?.observable.on(.next(Update(download: download, kind: .progress(CGFloat(progress.fractionCompleted)))))
        }
        self.progressObservers[download] = observer
    }

    private func file(for attachment: Attachment) -> File? {
        switch attachment.type {
        case .file(let filename, let contentType, _, _):
            return Files.attachmentFile(in: attachment.libraryId, key: attachment.key, filename: filename, contentType: contentType)

        case .url:
            return nil
        }
    }

    private func finish(download: Download, file: File, attachment: Attachment, parentKey: String, result: Result<(), Swift.Error>) {
        self.operations[download] = nil

        switch result {
        case .success:
            DDLogInfo("RemoteAttachmentDownloader: finished downloading \(download.key)")
            self.observable.on(.next(Update(download: download, kind: .ready(attachment))))
            self.errors[download] = nil

        case .failure(let error):
            DDLogError("RemoteAttachmentDownloader: failed to download attachment \(download.key), \(download.libraryId) - \(error)")

            let isCancelError = (error as? AttachmentDownloadOperation.Error) == .cancelled
            self.errors[download] = isCancelError ? nil : error

            if isCancelError {
                self.observable.on(.next(Update(download: download, kind: .cancelled)))
            } else {
                self.observable.on(.next(Update(download: download, kind: .failed)))
            }
        }
    }
}
