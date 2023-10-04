//
//  AttachmentDownloadOperation.swift
//  Zotero
//
//  Created by Michal Rentka on 23.02.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import Alamofire
import RxSwift
import CocoaLumberjackSwift

class AttachmentDownloadOperation: AsynchronousOperation {
    private enum State {
        case downloading, unzipping, done
    }

    enum Error: Swift.Error {
        case cancelled
    }

    private let file: File
    private let download: AttachmentDownloader.Download
    let progress: Progress
    private let userId: Int
    private let queue: DispatchQueue
    private unowned let apiClient: ApiClient
    private unowned let fileStorage: FileStorage
    private unowned let webDavController: WebDavController

    private var request: DownloadRequest?
    private var zipProgress: Progress?
    private var state: State?
    private var disposeBag: DisposeBag?

    var finishedDownload: ((Result<(), Swift.Error>) -> Void)?

    init(file: File, download: AttachmentDownloader.Download, progress: Progress, userId: Int, apiClient: ApiClient, webDavController: WebDavController, fileStorage: FileStorage, queue: DispatchQueue) {
        self.file = file
        self.download = download
        self.progress = progress
        self.userId = userId
        self.apiClient = apiClient
        self.webDavController = webDavController
        self.fileStorage = fileStorage
        self.queue = queue

        super.init()
    }

    override func main() {
        super.main()

        guard self.state == nil && !self.isCancelled else { return }

        self.startDownload()
    }

    private func startDownload() {
        let disposeBag = DisposeBag()
        var isCompressed = self.webDavController.sessionStorage.isEnabled && !self.download.libraryId.isGroupLibrary

        DDLogInfo("AttachmentDownloadOperation: start downloading \(self.download.key)")

        self.state = .downloading
        self.disposeBag = disposeBag

        self.downloadRequest(file: self.file, key: self.download.key, libraryId: self.download.libraryId, userId: self.userId)
            .flatMap { [weak self] request -> Observable<DownloadRequest> in
                let downloadProgress = request.downloadProgress
                var didAddProgress = false
                // Check headers on redirect to see whether downloaded file will be compressed zip or base file.
                let redirector = Redirector(behavior: .modify({ _, request, response -> URLRequest? in
                    if !isCompressed {
                        isCompressed = response.value(forHTTPHeaderField: "Zotero-File-Compressed") == "Yes"
                    }
                    if !didAddProgress {
                        // If downloaded file is compressed, add download progress as incomplete (90%) and reserve the rest for unzipping. Otherwise it's a complete progress (100%).
                        self?.progress.addChild(downloadProgress, withPendingUnitCount: (isCompressed ? 90 : 100))
                        didAddProgress = true
                    }
                    return request
                }))
                return Observable.just(request.redirect(using: redirector))
            }
            .subscribe(onNext: { [weak self] request in
                // Store download request so that it can be cancelled
                self?.request = request
                // Start request
                request.resume()
            }, onError: { [weak self] error in
                guard let self = self, !self.isCancelled else { return }

                if self.fileStorage.has(self.file) {
                    try? self.fileStorage.remove(self.file)
                }

                self.request = nil
                self.state = .done
                self.finish(with: .failure(error))
            }, onCompleted: { [weak self] in
                guard let self = self, !self.isCancelled else { return }

                self.request = nil
                self.state = .done

                // Check whether downloaded file is not corrupted.
                if let error = self.checkFileResponse(for: self.file) {
                    self.finish(with: .failure(error))
                    return
                }

                // Check whether file is compressed and should be unzipped.
                if isCompressed {
                    self.state = .unzipping
                    self.unzip()
                    return
                }

                // Finish download
                self.finish(with: .success(()))
            })
          .disposed(by: disposeBag)
    }

    private func finish(with result: Result<(), Swift.Error>) {
        DDLogInfo("AttachmentDownloadOperation: finished downloading \(self.download.key)")
        self.finishedDownload?(result)
        self.finish()
    }

    /// Unzip attachment download. Also add child progress to main progress.
    /// - parameter file: Zip file
    /// - parameter download: Download identifier
    /// - parameter parentKey: Parent key of attachment.
    /// - parameter progress: Main progress of whole download.
    private func unzip() {
        let zipProgress = Progress()
        inMainThread {
            self.progress.addChild(zipProgress, withPendingUnitCount: 10)
        }
        self.zipProgress = zipProgress

        let result = self._unzip(file: self.file, download: self.download, progress: zipProgress)

        self.zipProgress = nil
        self.state = .done

        self.finish(with: result)
    }

    private func _unzip(file: File, download: AttachmentDownloader.Download, progress: Progress) -> Result<(), Swift.Error> {
        let zipFile = file.copyWithExt("zip")

        do {
            // Rename downloaded file extension to zip
            if self.fileStorage.has(zipFile) {
                try self.fileStorage.remove(zipFile)
            }
            try self.fileStorage.move(from: file, to: zipFile)
            // Remove other contents of folder so that zip extraction doesn't fail
            let files: [File] = try self.fileStorage.contentsOfDirectory(at: zipFile.directory)
            for file in files {
                guard file.name != zipFile.name || file.ext != zipFile.ext else { continue }
                try? self.fileStorage.remove(file)
            }
            // Unzip it to the same directory
            try FileManager.default.unzipItem(at: zipFile.createUrl(), to: zipFile.createRelativeUrl(), progress: progress)
            // Try removing zip file, don't return error if it fails, we've got what we wanted.
            try? self.fileStorage.remove(zipFile)
            // Rename unzipped file if zip contained only 1 file and the names don't match
            let unzippedFiles: [File] = try self.fileStorage.contentsOfDirectory(at: file.directory)
            if unzippedFiles.count == 1, let unzipped = unzippedFiles.first, (unzipped.name != file.name) || (unzipped.ext != file.ext) {
                try? self.fileStorage.move(from: unzipped, to: file)
            }

            if self.fileStorage.has(file) {
                return .success(())
            }
            return .failure(AttachmentDownloader.Error.zipDidntContainRequestedFile)
        } catch let error {
            DDLogError("AttachmentDownloadOperation: unzip error - \(error)")
            return .failure(AttachmentDownloader.Error.cantUnzipSnapshot)
        }
    }

    private func downloadRequest(file: File, key: String, libraryId: LibraryIdentifier, userId: Int) -> Observable<DownloadRequest> {
        if case .custom = libraryId, self.webDavController.sessionStorage.isEnabled {
            return self.webDavController.download(key: key, file: file, queue: self.queue)
        }

        let request = FileRequest(libraryId: libraryId, userId: self.userId, key: key, destination: file)
        return self.apiClient.download(request: request, queue: self.queue)
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

    override func cancel() {
        super.cancel()

        DDLogInfo("AttachmentDownloadOperation: cancelled \(self.download.key)")

        guard let state = self.state else {
            self.finishedDownload?(.failure(Error.cancelled))
            return
        }

        self.state = nil

        switch state {
        case .downloading:
            // Download request is in progress, cancel by removing dispose bag.
            self.request?.cancel()
            self.disposeBag = nil
            self.request = nil

        case .unzipping:
            // Request already finished, cancel unzipping action.
            self.zipProgress?.cancel()
            self.zipProgress = nil
            // Try removing downloaded file.
            try? self.fileStorage.remove(Files.attachmentDirectory(in: self.download.libraryId, key: self.download.key))
        case .done: break
        }

        self.finishedDownload?(.failure(Error.cancelled))
    }
}
