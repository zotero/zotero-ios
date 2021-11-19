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
import RxAlamofire
import RxSwift
import ZIPFoundation

final class AttachmentDownloader {
    enum Error: Swift.Error {
        case incompatibleAttachment
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

    fileprivate struct Download: Hashable {
        let key: String
        let libraryId: LibraryIdentifier
    }

    private let userId: Int
    private unowned let apiClient: ApiClient
    private unowned let fileStorage: FileStorage
    private unowned let dbStorage: DbStorage
    private unowned let webDavController: WebDavController
    private let queue: DispatchQueue
    private let scheduler: SerialDispatchQueueScheduler
    private let disposeBag: DisposeBag
    let observable: PublishSubject<Update>

    private var downloadRequests: [Download: DownloadRequest]
    private var unzipRequests: [Download: Progress]
    private var progresses: [Download: (Progress, NSKeyValueObservation)]
    private var errors: [Download: Swift.Error]

    init(userId: Int, apiClient: ApiClient, fileStorage: FileStorage, dbStorage: DbStorage, webDavController: WebDavController) {
        let queue = DispatchQueue(label: "org.zotero.AttachmentDownloader.ProcessingQueue", qos: .userInteractive)

        self.userId = userId
        self.apiClient = apiClient
        self.fileStorage = fileStorage
        self.dbStorage = dbStorage
        self.webDavController = webDavController
        self.downloadRequests = [:]
        self.progresses = [:]
        self.unzipRequests = [:]
        self.queue = queue
        self.scheduler = SerialDispatchQueueScheduler(queue: queue, internalSerialQueueName: "org.zotero.AttachmentDownloader.ProcessingScheduler")
        self.errors = [:]
        self.observable = PublishSubject()
        self.disposeBag = DisposeBag()
    }

    // MARK: - Actions

    func downloadIfNeeded(attachment: Attachment, parentKey: String?) {
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
        self.progresses[download] = nil

        if let request = self.downloadRequests[download] {
            request.cancel()
            self.downloadRequests[download] = nil
            return
        }

        if let request = self.unzipRequests[download] {
            request.cancel()
            self.unzipRequests[download] = nil

            // Since zip file is already downloaded, try deleting it
            try? self.fileStorage.remove(Files.attachmentDirectory(in: libraryId, key: key))
        }
    }

    func data(for key: String, libraryId: LibraryIdentifier) -> (progress: CGFloat?, error: Swift.Error?) {
        let download = Download(key: key, libraryId: libraryId)
        let progress = (self.progresses[download]?.0.fractionCompleted).flatMap({ CGFloat($0) })
        return (progress, self.errors[download])
    }

    // MARK: - Helpers

    private func downloadRequest(file: File, key: String, libraryId: LibraryIdentifier, userId: Int) -> Observable<DownloadRequest> {
        if case .custom = libraryId, self.webDavController.sessionStorage.isEnabled {
            return self.webDavController.download(key: key, file: file, queue: self.queue)
                       .subscribe(on: self.scheduler)
        }

        let request = FileRequest(libraryId: libraryId, userId: self.userId, key: key, destination: file)
        return self.apiClient.download(request: request)
    }

    private func download(file: File, key: String, parentKey: String?, libraryId: LibraryIdentifier, hasLocalCopy: Bool) {
        let download = Download(key: key, libraryId: libraryId)

        guard self.downloadRequests[download] == nil && self.unzipRequests[download] == nil else { return }

        let progress = Progress(totalUnitCount: 100)
        let observer = progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            self?.observable.on(.next(Update(download: download, parentKey: parentKey, kind: .progress(CGFloat(progress.fractionCompleted)))))
        }

        self.errors[download] = nil
        self.progresses[download] = (progress, observer)

        // Send first update to immediately reflect new state
        self.observable.on(.next(Update(download: download, parentKey: parentKey, kind: .progress(0))))

        var isCompressed = self.webDavController.sessionStorage.isEnabled

        self.downloadRequest(file: file, key: key, libraryId: libraryId, userId: self.userId)
            .observe(on: MainScheduler.instance)
            .flatMap { request -> Observable<DownloadRequest> in
                let downloadProgress = request.downloadProgress
                // Check headers on redirect to see whether downloaded file will be compressed zip or base file.
                let redirector = Redirector(behavior: .modify({ task, request, response -> URLRequest? in
                    if !isCompressed {
                        isCompressed = response.value(forHTTPHeaderField: "Zotero-File-Compressed") == "Yes"
                    }
                    // If downloaded file is compressed, add download progress as incomplete (90%) and reserve the rest for unzipping. Otherwise it's a complete progress (100%).
                    progress.addChild(downloadProgress, withPendingUnitCount: (isCompressed ? 90 : 100))
                    return request
                }))
                return Observable.just(request.redirect(using: redirector))
            }
            .do(onNext: { [weak self] request in
                // Store download request so that it can be cancelled
                self?.downloadRequests[download] = request
            })
            .subscribe(onError: { [weak self] error in
                self?.finish(download: download, parentKey: parentKey, result: .failure(error), hasLocalCopy: hasLocalCopy)
            }, onCompleted: { [weak self] in
                guard let `self` = self else { return }
                if let error = self.checkFileResponse(for: file) {
                    self.finish(download: download, parentKey: parentKey, result: .failure(error), hasLocalCopy: hasLocalCopy)
                } else if isCompressed {
                    self.unzip(file: file, download: download, parentKey: parentKey, progress: progress, hasLocalCopy: hasLocalCopy)
                } else {
                    self.finish(download: download, parentKey: parentKey, result: .success(()), hasLocalCopy: hasLocalCopy)
                }
            })
          .disposed(by: self.disposeBag)
    }

    /// Alamofire bug workaround
    /// When the request returns 404 "Not found" Alamofire download doesn't recognize it and just downloads the file with content "Not found".
    private func checkFileResponse(for file: File) -> Swift.Error? {
        let size = self.fileStorage.size(of: file)
        if size == 0 || (size == 9 && (try? self.fileStorage.read(file)).flatMap({ String(data: $0, encoding: .utf8) }) == "Not found") {
            try? self.fileStorage.remove(file)
            return AFError.responseValidationFailed(reason: .unacceptableStatusCode(code: 404))
        }
        return nil
    }

    /// Unzip attachment download. Also add child progress to main progress.
    /// - parameter file: Zip file
    /// - parameter download: Download identifier
    /// - parameter parentKey: Parent key of attachment.
    /// - parameter progress: Main progress of whole download.
    private func unzip(file: File, download: Download, parentKey: String?, progress: Progress, hasLocalCopy: Bool) {
        let zipProgress = Progress()
        progress.addChild(zipProgress, withPendingUnitCount: 10)

        self.downloadRequests[download] = nil
        self.unzipRequests[download] = zipProgress

        self.queue.async { [weak self] in
            guard let `self` = self else { return }
            let result = self._unzip(file: file, download: download, parentKey: parentKey, progress: zipProgress)
            DispatchQueue.main.async { [weak self] in
                self?.finish(download: download, parentKey: parentKey, result: result, hasLocalCopy: hasLocalCopy)
            }
        }
    }

    private func _unzip(file: File, download: Download, parentKey: String?, progress: Progress) -> Result<(), Swift.Error> {
        let zipFile = file.copyWithExt("zip")

        do {
            // Rename downloaded file extension to zip
            try self.fileStorage.move(from: file, to: zipFile)
            // Remove other contents of folder so that zip extraction doesn't fail
            let files: [File] = try self.fileStorage.contentsOfDirectory(at: zipFile.directory)
            for file in files {
                guard file.name != zipFile.name && file.ext != zipFile.ext else { continue }
                try? self.fileStorage.remove(file)
            }
            // Unzip it to the same directory
            try FileManager.default.unzipItem(at: zipFile.createUrl(), to: zipFile.createRelativeUrl(), progress: progress)
            // Try removing zip file, don't return error if it fails, we've got what we wanted.
            try? self.fileStorage.remove(zipFile)

            return .success(())
        } catch let error {
            return .failure(error)
        }
    }

    private func finish(download: Download, parentKey: String?, result: Result<(), Swift.Error>, hasLocalCopy: Bool) {
        self.downloadRequests[download] = nil
        self.unzipRequests[download] = nil
        self.progresses[download] = nil

        switch result {
        case .success:
            self.errors[download] = nil
            self.observable.on(.next(Update(download: download, parentKey: parentKey, kind: .ready)))
            // Mark file as downloaded in DB
            try? self.dbStorage.createCoordinator().perform(request: MarkFileAsDownloadedDbRequest(key: download.key, libraryId: download.libraryId, downloaded: true))

        case .failure(let error):
            DDLogError("AttachmentDownloader: failed to download attachment \(download.key), \(download.libraryId) - \(error)")
            let isCancelError = (error as? Alamofire.AFError)?.isExplicitlyCancelledError == true || (error as? Archive.ArchiveError) == .cancelledOperation
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
