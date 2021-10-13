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

final class WebDavController {
    enum Error {
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
    }

    private unowned let apiClient: ApiClient
    let sessionStorage: WebDavSessionStorage
    private let queue: DispatchQueue
    private let scheduler: SerialDispatchQueueScheduler

    init(apiClient: ApiClient, sessionStorage: WebDavSessionStorage) {
        let queue = DispatchQueue(label: "org.zotero.WebDavController.queue", qos: .userInteractive)
        self.queue = queue
        self.scheduler = SerialDispatchQueueScheduler(queue: queue, internalSerialQueueName: "org.zotero.WebDavController.scheduler")
        self.apiClient = apiClient
        self.sessionStorage = sessionStorage
    }

    /// Creates url in WebDAV server of item which should be downloaded.
    /// - parameter key: Key of item to download.
    /// - returns: Single with url of item stored in WebDAV.
    func urlForDownload(key: String) -> Single<URL> {
        return self.checkServerIfNeeded()
                   .subscribe(on: self.scheduler)
                   .flatMap({ Single.just($0.appendingPathComponent("\(key).zip")) })
    }

    private func metadata(key: String, url: URL) -> Single<(Int, String)> {
        let request = WebDavDownloadRequest(url: url.appendingPathComponent(key + ".prop"))
        return self.apiClient.send(request: request, queue: self.queue)
                   .do(onError: { error in
                       DDLogError("WebDavController: \(key) item prop file not found - \(error)")
                   })
                   .flatMap({ data, _ -> Single<(Int, String)> in
                       let delegate = WebDavPropParserDelegate()
                       let parser = XMLParser(data: data)
                       parser.delegate = delegate

                       if parser.parse(), let mtime = delegate.mtime, let hash = delegate.fileHash {
                           return Single.just((mtime, hash))
                       } else {
                           DDLogError("WebDavController: \(key) item prop invalid. mtime=\(delegate.mtime.flatMap(String.init) ?? "missing"); hash=\(delegate.fileHash ?? "missing")")
                           return Single.error(Error.Download.itemPropInvalid)
                       }
                   })
    }

    private func checkServerIfNeeded() -> Single<URL> {
        if self.sessionStorage.isVerified {
            return self.createUrl()
        }
        return self.checkServer()
    }

    /// Checks whether WebDAV server is available and compatible.
    func checkServer() -> Single<URL> {
        DDLogInfo("WebDavController: checkServer")
        return self.createUrl()
                   .subscribe(on: self.scheduler)
                   .flatMap({ url in return self.checkIsDav(url: url) })
                   .flatMap({ url in return self.checkZoteroDirectory(url: url) })
                   .do(onSuccess: { [weak self] _ in
                       self?.sessionStorage.isVerified = true
                       DDLogInfo("WebDavController: file sync is successfully set up")
                   }, onError: { error in
                       DDLogError("WebDavController: checkServer failed - \(error)")
                   })
    }

    /// Checks whether server is WebDAV server.
    private func checkIsDav(url: URL) -> Single<URL> {
        let request = WebDavCheckRequest(url: url)
        return self.apiClient.send(request: request, queue: self.queue)
                             .flatMap({ _, response -> Single<URL> in
                                 guard response.allHeaderFields["DAV"] != nil else {
                                     return Single.error(Error.Verification.notDav)
                                 }
                                 return Single.just(url)
                             })
    }

    /// Checks whether WebDAV server contains Zotero directory and whether the directory is compatible.
    private func checkZoteroDirectory(url: URL) -> Single<URL> {
        return self.propFind(url: url)
                   .flatMap({ response -> Single<URL> in
                       if response.statusCode == 207 {
                           return self.checkWhetherReturns404ForMissingFile(url: url)
                                      .flatMap({ self.checkWritability(url: url) })
                                      .flatMap({ Single.just(url) })
                       }

                       if response.statusCode == 404 {
                           // Zotero directory wasn't found, see if parent directory exists
                           return self.checkWhetherParentAvailable(url: url)
                       }

                       return Single.just(url)
                   })
    }

    /// Checks whether WebDAV server has access to write files.
    private func checkWritability(url: URL) -> Single<()> {
        let request = WebDavTestWriteRequest(url: url)
        return self.apiClient.send(request: request, queue: self.queue)
                   .flatMap({ _ -> Single<()> in
                       return self.apiClient.send(request: WebDavDownloadRequest(endpoint: request.endpoint), queue: self.queue)
                                  .flatMap({ _, response in
                                      if response.statusCode == 404 {
                                          return Single.error(Error.Verification.fileMissingAfterUpload)
                                      }
                                      return Single.just(())
                                  })
                   })
                   .flatMap({ _ -> Single<()> in
                       return self.apiClient.send(request: WebDavDeleteRequest(endpoint: request.endpoint), queue: self.queue).flatMap({ _ in Single.just(()) })
                   })
    }

    /// Checks whether parent of given URL is available.
    private func checkWhetherParentAvailable(url: URL) -> Single<URL> {
        return self.propFind(url: url.deletingLastPathComponent())
                   .flatMap({ response -> Single<URL> in
                       if response.statusCode == 207 {
                           return Single.error(Error.Verification.zoteroDirNotFound)
                       } else {
                           return Single.error(Error.Verification.parentDirNotFound)
                       }
                   })
    }

    /// Checks whether WebDAV server correctly responds to a request for missing file.
    private func checkWhetherReturns404ForMissingFile(url: URL) -> Single<()> {
        return self.apiClient.send(request: WebDavNonexistentPropRequest(url: url), queue: self.queue)
                             .flatMap({ _, response -> Single<()> in
                                 if response.statusCode == 404 {
                                     return Single.just(())
                                 } else {
                                     return Single.error(Error.Verification.nonExistentFileNotMissing)
                                 }
                             })
    }

    /// Creates a propfind request for given url.
    private func propFind(url: URL) -> Single<HTTPURLResponse> {
        return self.apiClient.send(request: WebDavPropfindRequest(url: url), queue: self.queue).flatMap({ Single.just($1) })
    }

    /// Creates and validates WebDAV server URL based on stored session.
    private func createUrl() -> Single<URL> {
        return Single.create { [weak sessionStorage] subscriber in
            guard let sessionStorage = sessionStorage else {
                DDLogError("WebDavController: session storage not found")
                subscriber(.failure(Error.Verification.noUsername))
                return Disposables.create()
            }
            let username = sessionStorage.username
            guard !username.isEmpty else {
                DDLogError("WebDavController: username not found")
                subscriber(.failure(Error.Verification.noUsername))
                return Disposables.create()
            }
            let password = sessionStorage.password
            guard !password.isEmpty else {
                DDLogError("WebDavController: username not found")
                subscriber(.failure(Error.Verification.noPassword))
                return Disposables.create()
            }
            let url = sessionStorage.url
            guard !url.isEmpty else {
                DDLogError("WebDavController: url not found")
                subscriber(.failure(Error.Verification.noUrl))
                return Disposables.create()
            }

            let urlComponents = url.components(separatedBy: "/")
            guard !urlComponents.isEmpty else {
                DDLogError("WebDavController: url components empty - \(url)")
                subscriber(.failure(Error.Verification.invalidUrl))
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
                subscriber(.failure(Error.Verification.invalidUrl))
            }

            return Disposables.create()
        }
    }
}
