//
//  WebDavController.swift
//  Zotero
//
//  Created by Michal Rentka on 05.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxSwift
import SwiftUI

enum WebDavUploadResult {
    case exists
    case new(URL, File)
}

enum WebDavError {
    enum Verification: Swift.Error {
        case noUrl
        case noUsername
        case noPassword
        case invalidUrl
        case notDav
        case parentDirNotFound
        case zoteroDirNotFound
        case nonExistentFileNotMissing
        case fileMissingAfterUpload
    }

    enum Download: Swift.Error {
        case itemPropInvalid
        case notChanged
    }

    enum Upload: Swift.Error {
        case cantCreatePropData
    }
}

struct WebDavDeletionResult {
    let succeeded: Set<String>
    let missing: Set<String>
    let failed: Set<String>
}

protocol WebDavController: AnyObject {
    var sessionStorage: WebDavSessionStorage { get }

    func checkServer(queue: DispatchQueue) -> Single<URL>
    func urlForDownload(key: String, queue: DispatchQueue) -> Single<URL>
    func prepareForUpload(key: String, mtime: Int, hash: String, file: File, queue: DispatchQueue) -> Single<WebDavUploadResult>
    func finishUpload(key: String, result: Result<(Int, String, URL), Swift.Error>, file: File?, queue: DispatchQueue) -> Single<()>
    func delete(keys: [String], queue: DispatchQueue) -> Single<WebDavDeletionResult>
    func cancelDeletions()
}

final class WebDavControllerImpl: WebDavController {
    fileprivate enum MetadataResult {
        case unchanged
        case mtimeChanged(Int)
        case changed(URL)
        case new(URL)
    }

    private unowned let apiClient: ApiClient
    private unowned let dbStorage: DbStorage
    private unowned let fileStorage: FileStorage
    let sessionStorage: WebDavSessionStorage
    private let deletionQueue: OperationQueue

    init(apiClient: ApiClient, dbStorage: DbStorage, fileStorage: FileStorage, sessionStorage: WebDavSessionStorage) {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 4
        queue.qualityOfService = .userInteractive

        self.apiClient = apiClient
        self.dbStorage = dbStorage
        self.fileStorage = fileStorage
        self.sessionStorage = sessionStorage
        self.deletionQueue = queue
    }

    /// Creates url in WebDAV server of item which should be downloaded.
    /// - parameter key: Key of item to download.
    /// - returns: Single with url of item stored in WebDAV.
    func urlForDownload(key: String, queue: DispatchQueue) -> Single<URL> {
        return self.checkServerIfNeeded(queue: queue)
                   .flatMap({ Single.just($0.appendingPathComponent("\(key).zip")) })
    }

    /// Prepares for WebDAV upload. Checks .prop file to see whether the file has been modified. Creates a ZIP file to upload. Updates mtime in db in case it's the only thing that changed.
    /// - parameter key: Key of item to upload.
    /// - parameter mtime: Modification time of attachment.
    /// - parameter hash: MD5 hash of attachment.
    /// - parameter file: `File` location of attachment.
    /// - parameter queue: Processing queue.
    /// - returns: `UploadRequest` which contains either WebDAV URL and File location of file to upload or indicates that file is already available on WebDAV.
    func prepareForUpload(key: String, mtime: Int, hash: String, file: File, queue: DispatchQueue) -> Single<WebDavUploadResult> {
        DDLogInfo("WebDavController: prepare for upload")
        return self.checkServerIfNeeded(queue: queue)
                   .flatMap({ url -> Single<MetadataResult> in
                       return self.checkMetadata(key: key, mtime: mtime, hash: hash, url: url, queue: queue)
                   })
                   .flatMap({ result -> Single<WebDavUploadResult> in
                       switch result {
                       case .unchanged:
                           return Single.just(.exists)

                       case .new(let url):
                           return self.zip(file: file, key: key).flatMap({ return Single.just(.new(url, $0)) })

                       case .mtimeChanged(let mtime):
                           return self.update(mtime: mtime, key: key).flatMap({ Single.just(.exists) })

                       case .changed(let url):
                           // If metadata were available on WebDAV, but they changed, remove original .prop file.
                           return self.removeExistingMetadata(key: key, url: url, queue: queue)
                                      .flatMap({ self.zip(file: file, key: key) })
                                      .flatMap({ Single.just(.new(url, $0)) })
                       }
                   })
    }

    /// Finishes upload to WebDAV. If successful, uploads new metadata .prop file to WebDAV. In both cases removes temporary ZIP file created in `prepareForUpload`.
    /// - parameter key: Key of attachment item.
    /// - parameter result: Indicates whether file upload was successful. If successful, contains mtime, hash and WebDAV url.
    /// - parameter file: Optional `File` location of created temporary ZIP file. If available, removes ZIP.
    /// - parameter queue: Processing queue.
    /// - returns: Single indicating whether metadata were submitted and cleanup was successful.
    func finishUpload(key: String, result: Result<(Int, String, URL), Swift.Error>, file: File?, queue: DispatchQueue) -> Single<()> {
        switch result {
        case .success((let mtime, let hash, let url)):
            DDLogInfo("WebDavController: finish successful upload")
            return self.uploadMetadata(key: key, mtime: mtime, hash: hash, url: url, queue: queue)
                       .flatMap({ _ in
                           if let file = file {
                               return self.remove(file: file)
                           } else {
                               return Single.just(())
                           }
                       })

        case .failure(let error):
            DDLogError("WebDavController: finish failed upload - \(error)")
            if let file = file {
                return self.remove(file: file)
            } else {
                return Single.just(())
            }
        }
    }

    func delete(keys: [String], queue: DispatchQueue) -> Single<WebDavDeletionResult> {
        return self.checkServerIfNeeded(queue: queue)
                   .flatMap { url -> Single<WebDavDeletionResult> in
                       return self.performDeletions(withBaseUrl: url, keys: keys, queue: queue)
                   }
    }

    func cancelDeletions() {
        guard !self.deletionQueue.isSuspended else { return }
        self.deletionQueue.cancelAllOperations()
    }

    private func performDeletions(withBaseUrl url: URL, keys: [String], queue: DispatchQueue) -> Single<WebDavDeletionResult> {
        return Single.create { subscriber in
            var count = 0
            var operations: [ApiOperation] = []
            var succeeded: Set<String> = []
            var missing: Set<String> = []
            var failed: Set<String> = []

            let processResult: (String, Swift.Result<(Data?, HTTPURLResponse), Error>) -> Void = { key, result in
                switch result {
                case .success:
                    if !failed.contains(key) && !missing.contains(key) {
                        succeeded.insert(key)
                    }

                case .failure:
                    succeeded.remove(key)
                    missing.remove(key)
                    failed.insert(key)
                }

                count -= 1

                if count == 0 {
                    subscriber(.success(WebDavDeletionResult(succeeded: succeeded, missing: missing, failed: failed)))
                }
            }

            for key in keys {
                let propRequest = WebDavDeleteRequest(url: url.appendingPathComponent(key + ".prop"))
                let propOperation = self.apiClient.operation(from: propRequest, queue: queue) { result in
                    processResult(key, result)
                }
                operations.append(propOperation)

                let zipRequest = WebDavDeleteRequest(url: url.appendingPathComponent(key + ".zip"))
                let zipOperation = self.apiClient.operation(from: zipRequest, queue: queue) { result in
                    processResult(key, result)
                }
                operations.append(zipOperation)
            }

            count = operations.count

            self.deletionQueue.addOperations(operations, waitUntilFinished: false)

            return Disposables.create()
        }
    }

    private func delete(url: URL, queue: DispatchQueue) -> Observable<()> {
        let request = WebDavDeleteRequest(url: url)
        return self.apiClient.send(request: request, queue: queue).flatMap({ _ in return Single.just(()) }).asObservable()
    }

    private func update(mtime: Int, key: String) -> Single<()> {
        return Single.create { subscriber -> Disposable in
            do {
                try self.dbStorage.createCoordinator().perform(request: StoreMtimeForAttachmentDbRequest(mtime: mtime, key: key, libraryId: .custom(.myLibrary)))
            } catch let error {
                DDLogError("WebDavController: can't update mtime - \(error)")
            }
            return Disposables.create()
        }
    }

    private func remove(file: File) -> Single<()> {
        return Single.create { subscriber -> Disposable in
            try? self.fileStorage.remove(file)
            subscriber(.success(()))
            return Disposables.create()
        }
    }

    private func zip(file: File, key: String) -> Single<File> {
        return Single.create { subscriber -> Disposable in
            DDLogInfo("WebDavController: ZIP file for upload")

            do {
                let tmpFile = Files.temporaryZipUploadFile(key: key)
                try self.fileStorage.createDirectories(for: tmpFile)
                try? self.fileStorage.remove(tmpFile)
                try FileManager.default.zipItem(at: file.createUrl(), to: tmpFile.createUrl())
                subscriber(.success(tmpFile))
            } catch let error {
                DDLogError("WebDavController: can't zip file - \(error)")
                subscriber(.failure(error))
            }
            return Disposables.create()
        }
    }

    private func removeExistingMetadata(key: String, url: URL, queue: DispatchQueue) -> Single<()> {
        DDLogInfo("WebDavController: remove metadata for \(key)")
        return self.apiClient.send(request: WebDavDeleteRequest(url: url.appendingPathComponent(key + ".prop")), queue: queue)
                   .flatMap({ _ in return Single.just(()) })
    }

    private func uploadMetadata(key: String, mtime: Int, hash: String, url: URL, queue: DispatchQueue) -> Single<()> {
        DDLogInfo("WebDavController: upload metadata for \(key)")
        let metadataProp = "<properties version=\"1\"><mtime>\(mtime)</mtime><hash>\(hash)</hash></properties>"
        guard let data = metadataProp.data(using: .utf8) else { return Single.error(WebDavError.Upload.cantCreatePropData) }
        return self.apiClient.send(request: WebDavWriteRequest(url: url.appendingPathComponent(key + ".prop"), data: data), queue: queue)
                   .flatMap({ _ in return Single.just(()) })
    }

    private func checkMetadata(key: String, mtime: Int, hash: String, url: URL, queue: DispatchQueue) -> Single<MetadataResult> {
        DDLogInfo("WebDavController: check metadata for \(key)")
        return self.metadata(key: key, url: url, queue: queue)
                   .flatMap({ remoteData -> Single<MetadataResult> in
                       guard let (remoteMtime, remoteHash) = remoteData else { return Single.just(.new(url)) }

                       if hash == remoteHash {
                           return Single.just(mtime == remoteMtime ? .unchanged : .mtimeChanged(remoteMtime))
                       } else {
                           return Single.just(.changed(url))
                       }
                   })
    }

    /// Loads metadata of item from WebDAV server.
    /// - parameter key: Key of item.
    /// - parameter url: WebDAV url.
    /// - returns: Single containing mtime and hash.
    private func metadata(key: String, url: URL, queue: DispatchQueue) -> Single<(Int, String)?> {
        let request = WebDavDownloadRequest(url: url.appendingPathComponent(key + ".prop"))
        return self.apiClient.send(request: request, queue: queue)
                   .do(onError: { error in
                       DDLogError("WebDavController: \(key) item prop file error - \(error)")
                   })
                   .flatMap({ data, response -> Single<(Int, String)?> in
                       if response.statusCode == 404 {
                           DDLogInfo("WebDavController: \(key) item prop file not found")
                           return Single.just(nil)
                       }

                       let delegate = WebDavPropParserDelegate()
                       let parser = XMLParser(data: data)
                       parser.delegate = delegate

                       if parser.parse(), let mtime = delegate.mtime, let hash = delegate.fileHash {
                           return Single.just((mtime, hash))
                       } else {
                           DDLogError("WebDavController: \(key) item prop invalid. mtime=\(delegate.mtime.flatMap(String.init) ?? "missing"); hash=\(delegate.fileHash ?? "missing")")
                           return Single.error(WebDavError.Download.itemPropInvalid)
                       }
                   })
    }

    /// If server is not verified, performs verification first.
    /// - returns: URL of WebDAV server after verification or immediately if verified.
    private func checkServerIfNeeded(queue: DispatchQueue) -> Single<URL> {
        if self.sessionStorage.isVerified {
            return self.createUrl()
        }
        return self.checkServer(queue: queue)
    }

    /// Checks whether WebDAV server is available and compatible.
    func checkServer(queue: DispatchQueue) -> Single<URL> {
        DDLogInfo("WebDavController: checkServer")
        return self.createUrl()
                   .flatMap({ url in return self.checkIsDav(url: url, queue: queue) })
                   .flatMap({ url in return self.checkZoteroDirectory(url: url, queue: queue) })
                   .do(onSuccess: { [weak self] _ in
                       self?.sessionStorage.isVerified = true
                       DDLogInfo("WebDavController: file sync is successfully set up")
                   }, onError: { error in
                       DDLogError("WebDavController: checkServer failed - \(error)")
                   })
    }

    /// Checks whether server is WebDAV server.
    private func checkIsDav(url: URL, queue: DispatchQueue) -> Single<URL> {
        let request = WebDavCheckRequest(url: url)
        return self.apiClient.send(request: request, queue: queue)
                             .flatMap({ _, response -> Single<URL> in
                                 guard response.allHeaderFields["DAV"] != nil else {
                                     return Single.error(WebDavError.Verification.notDav)
                                 }
                                 return Single.just(url)
                             })
    }

    /// Checks whether WebDAV server contains Zotero directory and whether the directory is compatible.
    private func checkZoteroDirectory(url: URL, queue: DispatchQueue) -> Single<URL> {
        return self.propFind(url: url, queue: queue)
                   .flatMap({ response -> Single<URL> in
                       if response.statusCode == 207 {
                           return self.checkWhetherReturns404ForMissingFile(url: url, queue: queue)
                               .flatMap({ self.checkWritability(url: url, queue: queue) })
                                      .flatMap({ Single.just(url) })
                       }

                       if response.statusCode == 404 {
                           // Zotero directory wasn't found, see if parent directory exists
                           return self.checkWhetherParentAvailable(url: url, queue: queue)
                       }

                       return Single.just(url)
                   })
    }

    /// Checks whether WebDAV server has access to write files.
    private func checkWritability(url: URL, queue: DispatchQueue) -> Single<()> {
        let request = WebDavTestWriteRequest(url: url)
        return self.apiClient.send(request: request, queue: queue)
                   .flatMap({ _ -> Single<()> in
                       return self.apiClient.send(request: WebDavDownloadRequest(endpoint: request.endpoint), queue: queue)
                                  .flatMap({ _, response in
                                      if response.statusCode == 404 {
                                          return Single.error(WebDavError.Verification.fileMissingAfterUpload)
                                      }
                                      return Single.just(())
                                  })
                   })
                   .flatMap({ _ -> Single<()> in
                       return self.apiClient.send(request: WebDavDeleteRequest(endpoint: request.endpoint), queue: queue).flatMap({ _ in Single.just(()) })
                   })
    }

    /// Checks whether parent of given URL is available.
    private func checkWhetherParentAvailable(url: URL, queue: DispatchQueue) -> Single<URL> {
        return self.propFind(url: url.deletingLastPathComponent(), queue: queue)
                   .flatMap({ response -> Single<URL> in
                       if response.statusCode == 207 {
                           return Single.error(WebDavError.Verification.zoteroDirNotFound)
                       } else {
                           return Single.error(WebDavError.Verification.parentDirNotFound)
                       }
                   })
    }

    /// Checks whether WebDAV server correctly responds to a request for missing file.
    private func checkWhetherReturns404ForMissingFile(url: URL, queue: DispatchQueue) -> Single<()> {
        return self.apiClient.send(request: WebDavNonexistentPropRequest(url: url), queue: queue)
                             .flatMap({ _, response -> Single<()> in
                                 if response.statusCode == 404 {
                                     return Single.just(())
                                 } else {
                                     return Single.error(WebDavError.Verification.nonExistentFileNotMissing)
                                 }
                             })
    }

    /// Creates a propfind request for given url.
    private func propFind(url: URL, queue: DispatchQueue) -> Single<HTTPURLResponse> {
        return self.apiClient.send(request: WebDavPropfindRequest(url: url), queue: queue).flatMap({ Single.just($1) })
    }

    /// Creates and validates WebDAV server URL based on stored session.
    private func createUrl() -> Single<URL> {
        return Single.create { [weak sessionStorage] subscriber in
            guard let sessionStorage = sessionStorage else {
                DDLogError("WebDavController: session storage not found")
                subscriber(.failure(WebDavError.Verification.noUsername))
                return Disposables.create()
            }
            let username = sessionStorage.username
            guard !username.isEmpty else {
                DDLogError("WebDavController: username not found")
                subscriber(.failure(WebDavError.Verification.noUsername))
                return Disposables.create()
            }
            let password = sessionStorage.password
            guard !password.isEmpty else {
                DDLogError("WebDavController: username not found")
                subscriber(.failure(WebDavError.Verification.noPassword))
                return Disposables.create()
            }
            let url = sessionStorage.url
            guard !url.isEmpty else {
                DDLogError("WebDavController: url not found")
                subscriber(.failure(WebDavError.Verification.noUrl))
                return Disposables.create()
            }

            let urlComponents = url.components(separatedBy: "/")
            guard !urlComponents.isEmpty else {
                DDLogError("WebDavController: url components empty - \(url)")
                subscriber(.failure(WebDavError.Verification.invalidUrl))
                return Disposables.create()
            }

            let hostComponents = (urlComponents.first ?? "").components(separatedBy: ":")
            let host = hostComponents.first
            let port = hostComponents.last.flatMap(Int.init)

            let path: String
            if urlComponents.count == 1 {
                path = "/zotero/"
            } else {
                path = "/" + urlComponents.dropFirst().filter({ !$0.isEmpty }).joined(separator: "/") + "/zotero/"
            }

            var components = URLComponents()
            components.scheme = sessionStorage.scheme.rawValue
            components.user = username
            components.password = password
            components.host = host
            components.path = path
            components.port = port

            if let url = components.url {
                subscriber(.success(url))
            } else {
                DDLogError("WebDavController: could not create url from components. url=\(url); host=\(host ?? "missing"); path=\(path); port=\(port.flatMap(String.init) ?? "missing")")
                subscriber(.failure(WebDavError.Verification.invalidUrl))
            }

            return Disposables.create()
        }
    }
}
