//
//  AttachmentDownloader.swift
//  Zotero
//
//  Created by Michal Rentka on 11/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import Alamofire
import ZIPFoundation
import RxAlamofire
import RxSwift

final class AttachmentDownloader {
    enum Error: Swift.Error {
        case incompatibleAttachment, fileMissingRemotely
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
    private let apiClient: ApiClient
    private let fileStorage: FileStorage
    private let unzipQueue: DispatchQueue
    private let disposeBag: DisposeBag
    let observable: PublishSubject<Update>

    private var downloadRequests: [Download: DownloadRequest]
    private var unzipRequests: [Download: Progress]
    private var progresses: [Download: (Progress, NSKeyValueObservation)]
    private var errors: [Download: Swift.Error]

    init(userId: Int, apiClient: ApiClient, fileStorage: FileStorage) {
        self.userId = userId
        self.apiClient = apiClient
        self.fileStorage = fileStorage
        self.downloadRequests = [:]
        self.progresses = [:]
        self.unzipRequests = [:]
        self.unzipQueue = DispatchQueue(label: "org.zotero.AttachmentDownloader.UnzipQueue", qos: .userInteractive)
        self.errors = [:]
        self.observable = PublishSubject()
        self.disposeBag = DisposeBag()
    }

    // MARK: - Actions

    func download(attachment: Attachment, parentKey: String?) {
        switch attachment.type {
        case .url:
            self.observable.on(.next(Update(key: attachment.key, parentKey: parentKey, libraryId: attachment.libraryId, kind: .ready)))
        case .file(let filename, let contentType, let location, let linkType):
            switch linkType {
            case .linkedFile, .embeddedImage:
                return self.observable.on(.next(Update(key: attachment.key, parentKey: parentKey, libraryId: attachment.libraryId, kind: .failed(Error.incompatibleAttachment))))
            case .importedFile, .importedUrl:
                switch location {
                case .local:
                    self.observable.on(.next(Update(key: attachment.key, parentKey: parentKey, libraryId: attachment.libraryId, kind: .ready)))
                case .remoteMissing:
                    self.observable.on(.next(Update(key: attachment.key, parentKey: parentKey, libraryId: attachment.libraryId, kind: .failed(Error.fileMissingRemotely))))
                case .remote:
                    let file = Files.newAttachmentFile(in: attachment.libraryId, key: attachment.key, filename: filename, contentType: contentType)
                    self.download(file: file, key: attachment.key, parentKey: parentKey, libraryId: attachment.libraryId)
                }
            }
        }
    }

    func cancel(key: String, libraryId: LibraryIdentifier) {
        let download = Download(key: key, libraryId: libraryId)
        self.downloadRequests[download]?.cancel()
        self.unzipRequests[download]?.cancel()
        self.progresses[download] = nil
    }

    func data(for key: String, libraryId: LibraryIdentifier) -> (progress: CGFloat?, error: Swift.Error?) {
        let download = Download(key: key, libraryId: libraryId)
        let progress = (self.progresses[download]?.0.fractionCompleted).flatMap({ CGFloat($0) })
        return (progress, self.errors[download])
    }

    // MARK: - Helpers

    private func download(file: File, key: String, parentKey: String?, libraryId: LibraryIdentifier) {
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

        var isCompressed = false

        let request = FileRequest(data: .internal(libraryId, self.userId, key), destination: file)
        self.apiClient.download(request: request)
                      .observeOn(MainScheduler.instance)
                      .flatMap { request -> Observable<DownloadRequest> in
                          let downloadProgress = request.downloadProgress
                          // Check headers on redirect to see whether downloaded file will be compressed zip or base file.
                          let redirector = Redirector(behavior: .modify({ task, request, response -> URLRequest? in
                              isCompressed = response.value(forHTTPHeaderField: "Zotero-File-Compressed") == "Yes"
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
                          self?.finish(download: download, parentKey: parentKey, result: .failure(error))
                      }, onCompleted: { [weak self] in
                          guard let `self` = self else { return }
                          if let error = self.checkFileResponse(for: file) {
                              self.finish(download: download, parentKey: parentKey, result: .failure(error))
                          } else if isCompressed {
                              self.unzip(file: file, download: download, parentKey: parentKey, progress: progress)
                          } else {
                              self.finish(download: download, parentKey: parentKey, result: .success(()))
                          }
                      })
                    .disposed(by: self.disposeBag)
    }

    /// Alamofire bug workaround
    /// When the request returns 404 "Not found" Alamofire download doesn't recognize it and just downloads the file with content "Not found".
    private func checkFileResponse(for file: File) -> Swift.Error? {
        if self.fileStorage.size(of: file) == 9 &&
           (try? self.fileStorage.read(file)).flatMap({ String(data: $0, encoding: .utf8) }) == "Not found" {
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
    private func unzip(file: File, download: Download, parentKey: String?, progress: Progress) {
        let zipProgress = Progress()
        progress.addChild(zipProgress, withPendingUnitCount: 10)

        self.downloadRequests[download] = nil
        self.unzipRequests[download] = zipProgress

        self.unzipQueue.async { [weak self] in
            guard let `self` = self else { return }
            let result = self._unzip(file: file, download: download, parentKey: parentKey, progress: zipProgress)
            DispatchQueue.main.async { [weak self] in
                self?.finish(download: download, parentKey: parentKey, result: result)
            }
        }
    }

    private func _unzip(file: File, download: Download, parentKey: String?, progress: Progress) -> Result<(), Swift.Error> {
        let zipFile = file.copyWithExt("zip")

        do {
            // Rename downloaded file extension to zip
            try self.fileStorage.move(from: file, to: zipFile)
            // Unzip it to the same directory
            try FileManager.default.unzipItem(at: zipFile.createUrl(), to: zipFile.createRelativeUrl(), progress: progress)
            // Try removing zip file, don't return error if it fails, we've got what we wanted.
            try? self.fileStorage.remove(zipFile)

            return .success(())
        } catch let error {
            return .failure(error)
        }
    }

    private func finish(download: Download, parentKey: String?, result: Result<(), Swift.Error>) {
        self.downloadRequests[download] = nil
        self.unzipRequests[download] = nil
        self.progresses[download] = nil

        switch result {
        case .success:
            self.errors[download] = nil
            self.observable.on(.next(Update(download: download, parentKey: parentKey, kind: .ready)))

        case .failure(let error):
            let isCancelError = (error as? Alamofire.AFError)?.isExplicitlyCancelledError == true || (error as? Archive.ArchiveError) == .cancelledOperation
            self.errors[download] = isCancelError ? nil : error
            self.observable.on(.next(Update(download: download, parentKey: parentKey, kind: (isCancelError ? .cancelled : .failed(error)))))
        }
    }
}
