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
            case ready
            case failed
            case cancelled
        }

        let key: String
        let libraryId: LibraryIdentifier
        let kind: Kind

        fileprivate init(download: Download, kind: Kind) {
            self.key = download.key
            self.libraryId = download.libraryId
            self.kind = kind
        }
    }

    private let queue: DispatchQueue
    private let operationQueue: OperationQueue
    private let disposeBag: DisposeBag
    private unowned let apiClient: ApiClient
    private unowned let fileStorage: FileStorage
    private unowned let dbStorage: DbStorage
    private unowned let schemaController: SchemaController

    let observable: PublishSubject<Update>

    private var operations: [Download: RemoteAttachmentDownloadOperation]
    private var progressObservers: [Download: NSKeyValueObservation]

    init(apiClient: ApiClient, fileStorage: FileStorage, dbStorage: DbStorage, schemaController: SchemaController) {
        let queue = DispatchQueue(label: "org.zotero.AttachmentDownloader.ProcessingQueue", qos: .userInteractive, attributes: .concurrent)
        let operationQueue = OperationQueue()
        operationQueue.maxConcurrentOperationCount = 2
        operationQueue.qualityOfService = .userInitiated
        operationQueue.underlyingQueue = queue

        self.apiClient = apiClient
        self.fileStorage = fileStorage
        self.schemaController = schemaController
        self.dbStorage = dbStorage
        self.operationQueue = operationQueue
        self.queue = queue
        self.observable = PublishSubject()
        self.operations = [:]
        self.progressObservers = [:]
        self.disposeBag = DisposeBag()
    }

    func download(data: [(Attachment, URL, String)]) {
        self.queue.async(flags: .barrier) { [weak self] in
            guard let `self` = self else { return }

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
                guard let `self` = self else { return }
                self.finish(download: download, file: file, attachment: attachment, parentKey: parentKey, result: result)
            }
        }
        operation.progressHandler = { [weak self] progress in
            self?.queue.async(flags: .barrier) {
                guard let `self` = self else { return }
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

            let localizedType = self.schemaController.localized(itemType: ItemTypes.attachment) ?? ItemTypes.attachment
            let request = CreateAttachmentWithParentDbRequest(attachment: attachment, parentKey: parentKey, localizedType: localizedType)

            do {
                try self.dbStorage.perform(request: request, on: self.queue)
                self.observable.on(.next(Update(download: download, kind: .ready)))
            } catch let error {
                DDLogError("RemoteAttachmentDownloader: can't store attachment after download - \(error)")
                // Storing item failed, remove downloaded file
                try? self.fileStorage.remove(file)
                self.observable.on(.next(Update(download: download, kind: .failed)))
            }

        case .failure(let error):
            DDLogError("RemoteAttachmentDownloader: failed to download attachment \(download.key), \(download.libraryId) - \(error)")

            let isCancelError = (error as? AttachmentDownloadOperation.Error) == .cancelled
            if isCancelError {
                self.observable.on(.next(Update(download: download, kind: .cancelled)))
            } else {
                self.observable.on(.next(Update(download: download, kind: .failed)))
            }
        }
    }
}
