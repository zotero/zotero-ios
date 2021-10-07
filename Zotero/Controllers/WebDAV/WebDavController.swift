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
    enum Error: Swift.Error {
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
    }

    private unowned let apiClient: ApiClient
    let sessionStorage: WebDavSessionStorage

    private var verified: Bool

    init(apiClient: ApiClient, sessionStorage: WebDavSessionStorage) {
        self.apiClient = apiClient
        self.sessionStorage = sessionStorage
        self.verified = false
    }

    func checkServer() -> Single<()> {
        return self.createUrl()
                   .flatMap({ url in return self.checkIsDav(url: url) })
                   .flatMap({ url in return self.checkZoteroDirectory(url: url) })
                   .flatMap({ _ in return Single.just(()) })
                   .do(onSuccess: { [weak self] _ in
                       self?.verified = true
                       DDLogInfo("WebDavController: file sync is successfully set up")
                   })
    }

    private func checkIsDav(url: URL) -> Single<URL> {
        let request = WebDavRequest(url: url, httpMethod: .options, acceptableStatusCodes: [200, 404])
        return self.apiClient.send(request: request)
                             .flatMap({ _, response -> Single<URL> in
                                 guard response.allHeaderFields["DAV"] != nil else {
                                     return Single.error(Error.Verification.notDav)
                                 }
                                 return Single.just(url)
                             })
    }

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

    private func checkWritability(url: URL) -> Single<()> {
        let testUrl = url.appendingPathComponent("zotero-test-file.prop")
        let request = WebDavRequest(url: testUrl, httpMethod: .put, parameters: " ".data(using: .utf8)?.asParameters(), parameterEncoding: .data, headers: nil, acceptableStatusCodes: [200, 201, 204])
        return self.apiClient.send(request: request)
                   .flatMap({ _ -> Single<()> in
                       let request = WebDavRequest(url: testUrl, httpMethod: .get, acceptableStatusCodes: [200, 404])
                       return self.apiClient.send(request: request)
                                  .flatMap({ _, response in
                                      if response.statusCode == 404 {
                                          return Single.error(Error.Verification.fileMissingAfterUpload)
                                      }
                                      return Single.just(())
                                  })
                   })
                   .flatMap({ _ -> Single<()> in
                       let request = WebDavRequest(url: testUrl, httpMethod: .delete, acceptableStatusCodes: [200, 204])
                       return self.apiClient.send(request: request).flatMap({ _ in Single.just(()) })
                   })
    }

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

    private func checkWhetherReturns404ForMissingFile(url: URL) -> Single<()> {
        let request = WebDavRequest(url: url.appendingPathComponent("nonexistent.prop"), httpMethod: .get, acceptableStatusCodes: Set(200..<300).union([404]))
        return self.apiClient.send(request: request)
                             .flatMap({ _, response -> Single<()> in
                                 if response.statusCode == 404 {
                                     return Single.just(())
                                 } else {
                                     return Single.error(Error.Verification.nonExistentFileNotMissing)
                                 }
                             })
    }

    private func propFind(url: URL) -> Single<HTTPURLResponse> {
        // IIS 5.1 requires at least one property in PROPFIND
        let xmlData = "<propfind xmlns='DAV:'><prop><getcontentlength/></prop></propfind>".data(using: .utf8)
        let request = WebDavRequest(url: url, httpMethod: .propfind, parameters: xmlData?.asParameters(), parameterEncoding: .data,
                                    headers: ["Content-Type": "text/xml; charset=utf-8", "Depth": "0"], acceptableStatusCodes: [207, 404])
        return self.apiClient.send(request: request).flatMap({ Single.just($1) })
    }

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
                subscriber(.failure(Error.Verification.invalidUrl))
            }

            return Disposables.create()
        }
    }
}
