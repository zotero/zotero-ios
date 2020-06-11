//
//  FileDownloader.swift
//  Zotero
//
//  Created by Michal Rentka on 11/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import Alamofire
import RxAlamofire
import RxSwift

class FileDownloader {
    struct Update {
        enum Kind {
            case progress(CGFloat)
            case downloaded
            case failed(Error)
            case cancelled

            var isDownloaded: Bool {
                switch self {
                case .downloaded: return true
                default: return false
                }
            }
        }

        let key: String
        let libraryId: LibraryIdentifier
        let kind: Kind
    }

    private struct Download: Hashable {
        let key: String
        let libraryId: LibraryIdentifier
    }

    private let userId: Int
    private let apiClient: ApiClient
    private let fileStorage: FileStorage
    private let disposeBag: DisposeBag
    let observable: PublishSubject<Update>

    private var requests: [Download: DownloadRequest]
    private var progresses: [Download: CGFloat]
    private var errors: [Download: Error]

    init(userId: Int, apiClient: ApiClient, fileStorage: FileStorage) {
        self.userId = userId
        self.apiClient = apiClient
        self.fileStorage = fileStorage
        self.requests = [:]
        self.progresses = [:]
        self.errors = [:]
        self.observable = PublishSubject()
        self.disposeBag = DisposeBag()
    }

    func download(file: File, key: String, libraryId: LibraryIdentifier) {
        let download = Download(key: key, libraryId: libraryId)

        guard self.requests[download] == nil else { return }

        self.errors[download] = nil
        self.progresses[download] = 0

        // Send first update to immediately reflect new state
        self.observable.on(.next(Update(key: download.key, libraryId: download.libraryId, kind: .progress(0))))

        let request = FileRequest(data: .internal(libraryId, self.userId, key), destination: file)
        self.apiClient.download(request: request)
                      .do(onNext: { [weak self] request in
                          self?.requests[download] = request
                      })
                      .flatMap { request in
                          return request.rx.progress()
                      }
                      .observeOn(MainScheduler.instance)
                      .subscribe(onNext: { [weak self] progress in
                          guard let `self` = self else { return }
                          let progress = CGFloat(progress.completed)
                          self.progresses[download] = progress
                          self.observable.on(.next(Update(key: download.key, libraryId: download.libraryId, kind: .progress(progress))))
                      }, onError: { [weak self] error in
                          self?.didFinish(download: download, error: error)
                      }, onCompleted: { [weak self] in
                          self?.didFinish(download: download, error: self?.checkFileResponse(for: file))
                      })
                      .disposed(by: self.disposeBag)
    }

    /// Alamofire bug workaround
    /// When the request returns 404 "Not found" Alamofire download doesn't recognize it and just downloads the file with content "Not found".
    private func checkFileResponse(for file: File) -> Error? {
        if self.fileStorage.size(of: file) == 9 &&
           (try? self.fileStorage.read(file)).flatMap({ String(data: $0, encoding: .utf8) }) == "Not found" {
            try? self.fileStorage.remove(file)
            return AFError.responseValidationFailed(reason: .unacceptableStatusCode(code: 404))
        }
        return nil
    }

    private func didFinish(download: Download, error: Error?) {
        let isCancelError = error.flatMap({ ($0 as NSError).code == NSURLErrorCancelled }) == true

        self.requests[download] = nil
        self.progresses[download] = nil
        self.errors[download] = isCancelError ? nil : error

        let updateKind: Update.Kind
        if let error = error {
            if isCancelError {
                updateKind = .cancelled
            } else {
                updateKind = .failed(error)
            }
        } else {
            updateKind = .downloaded
        }

        self.observable.on(.next(Update(key: download.key, libraryId: download.libraryId, kind: updateKind)))
    }

    func cancel(key: String, libraryId: LibraryIdentifier) {
        self.requests[Download(key: key, libraryId: libraryId)]?.cancel()
    }

    func data(for key: String, libraryId: LibraryIdentifier) -> (CGFloat?, Error?) {
        let download = Download(key: key, libraryId: libraryId)
        return (self.progresses[download], self.errors[download])
    }
}
