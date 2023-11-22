//
//  RemoteAttachmentDownloadOperation.swift
//  Zotero
//
//  Created by Michal Rentka on 20.05.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import Alamofire
import RxSwift
import CocoaLumberjackSwift

class RemoteAttachmentDownloadOperation: AsynchronousOperation {
    private enum State {
        case downloading, done
    }

    enum Error: Swift.Error {
        case downloadNotPdf
        case cancelled
    }

    private let url: URL
    private let file: File
    let progress: Progress?
    private let queue: DispatchQueue
    private unowned let apiClient: ApiClient
    private unowned let fileStorage: FileStorage

    private var request: DownloadRequest?
    private var state: State?
    private var disposeBag: DisposeBag?

    var progressHandler: ((Progress) -> Void)?
    var finishedDownload: ((Result<(), Swift.Error>) -> Void)?

    init(url: URL, file: File, progress: Progress, apiClient: ApiClient, fileStorage: FileStorage, queue: DispatchQueue) {
        self.url = url
        self.file = file
        self.progress = progress
        self.apiClient = apiClient
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

        DDLogInfo("RemoteAttachmentDownloadOperation: start downloading \(self.url.absoluteString)")

        self.state = .downloading
        self.disposeBag = disposeBag

        let request = FileRequest(url: self.url, destination: self.file)
        self.apiClient.download(request: request, queue: self.queue)
            .subscribe(onNext: { [weak self] request in
                // Store download request so that it can be cancelled
                self?.progress?.addChild(request.downloadProgress, withPendingUnitCount: 100)
                self?.progressHandler?(request.downloadProgress)
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
                    try? self.fileStorage.remove(self.file)
                    self.finish(with: .failure(error))
                    return
                }

                // Finish download
                self.finish(with: .success(()))
            })
          .disposed(by: disposeBag)
    }

    private func finish(with result: Result<(), Swift.Error>) {
        DDLogInfo("RemoteAttachmentDownloadOperation: finished downloading \(self.url.absoluteString)")
        self.finishedDownload?(result)
        self.finish()
    }

    /// Alamofire bug workaround
    /// When the request returns 404 "Not found" Alamofire download doesn't recognize it and just downloads the file with content "Not found".
    private func checkFileResponse(for file: File) -> Swift.Error? {
        let size = self.fileStorage.size(of: file)
        if size == 0 || (size == 9 && (try? self.fileStorage.read(file)).flatMap({ String(data: $0, encoding: .utf8) }) == "Not found") {
            return AFError.responseValidationFailed(reason: .unacceptableStatusCode(code: 404))
        }
        if file.mimeType == "application/pdf" && !self.fileStorage.isPdf(file: file) {
            return Error.downloadNotPdf
        }
        return nil
    }

    override func cancel() {
        super.cancel()

        DDLogInfo("RemoteAttachmentDownloadOperation: cancelled \(self.url.absoluteString)")

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
            
        case .done:
            break
        }

        self.finishedDownload?(.failure(Error.cancelled))
    }
}
