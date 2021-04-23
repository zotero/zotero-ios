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

final class FileDownloader {
    struct Update {
        enum Kind {
            case progress(CGFloat)
            case downloaded(isCompressed: Bool)
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

    func download(file: File, key: String, parentKey: String?, libraryId: LibraryIdentifier) {
        let download = Download(key: key, libraryId: libraryId)

        guard self.requests[download] == nil else { return }

        self.errors[download] = nil
        self.progresses[download] = 0

        // Send first update to immediately reflect new state
        self.observable.on(.next(Update(download: download, parentKey: parentKey, kind: .progress(0))))

        var isCompressed = false

        let request = FileRequest(data: .internal(libraryId, self.userId, key), destination: file)
        self.apiClient.download(request: request)
                      .observeOn(MainScheduler.instance)
                      .do(onNext: { [weak self] request in
                          self?.requests[download] = request
                      })
                      .flatMap { request -> Observable<RxProgress> in
                          let redirector = Redirector(behavior: .modify({ task, request, response -> URLRequest? in
                              isCompressed = response.value(forHTTPHeaderField: "Zotero-File-Compressed") == "Yes"
                              return request
                          }))
                          return request.redirect(using: redirector).rx.progress()
                      }
                      .subscribe(onNext: { [weak self] progress in
                          guard let `self` = self else { return }
                          let progress = CGFloat(progress.completed)
                          self.progresses[download] = progress
                          self.observable.on(.next(Update(download: download, parentKey: parentKey, kind: .progress(progress))))
                      }, onError: { [weak self] error in
                          self?.didFinish(download: download, parentKey: parentKey, result: .failure(error))
                      }, onCompleted: { [weak self] in
                          guard let `self` = self else { return }
                          if let error = self.checkFileResponse(for: file) {
                              self.didFinish(download: download, parentKey: parentKey, result: .failure(error))
                              return
                          }
                          self.didFinish(download: download, parentKey: parentKey, result: .success(isCompressed))
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

    private func didFinish(download: Download, parentKey: String?, result: Result<Bool, Error>) {
        self.requests[download] = nil
        self.progresses[download] = nil

        let updateKind: Update.Kind

        switch result {
        case .success(let isCompressed):
            self.errors[download] = nil
            updateKind = .downloaded(isCompressed: isCompressed)

        case .failure(let error):
            let isCancelError = (error as? Alamofire.AFError)?.isExplicitlyCancelledError == true
            self.errors[download] = isCancelError ? nil : error
            updateKind = isCancelError ? .cancelled : .failed(error)
        }

        self.observable.on(.next(Update(download: download, parentKey: parentKey, kind: updateKind)))
    }

    func cancel(key: String, libraryId: LibraryIdentifier) {
        self.requests[Download(key: key, libraryId: libraryId)]?.cancel()
    }

    func data(for key: String, libraryId: LibraryIdentifier) -> (progress: CGFloat?, error: Error?) {
        let download = Download(key: key, libraryId: libraryId)
        return (self.progresses[download], self.errors[download])
    }
}
