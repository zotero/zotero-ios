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
    private static let url = URL(string: "http://michalrentka:utorok@192.168.0.104:8080/zotero/")!

    enum Error: Swift.Error {
        case expired
        case unknownResponse(code: Int, url: String)
        case noScheme
        case schemeInvalid
        case noUrl
        case noUsername
        case noPassword
        case invalidUrl
        case notDav
        case parentDirNotFound
        case zoteroDirNotFound
        case nonExistentFileNotMissing
    }

    private let urlSession: URLSession
    private let sessionStorage: WebDavSessionStorage

    private var verified: Bool

    init(sessionStorage: WebDavSessionStorage) {
        self.urlSession = URLSession(configuration: .default)
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
        var request = URLRequest(url: url)
        request.httpMethod = "OPTIONS"
        return self.urlSession.rx.response(request: request)
                   .validate(successCodes: [200, 404])
                   .flatMap({ response, _ -> Observable<()> in
                       guard response.allHeaderFields["DAV"] != nil else {
                           return Observable.error(Error.notDav)
                       }
                       return Observable.just(())
                   })
                   .asSingle()
                   .flatMap({ _ in Single.just(url) })
    }

    private func checkZoteroDirectory(url: URL) -> Single<URL> {
        return self.propFind(url: url)
                   .flatMap({ response, _ -> Observable<()> in
                       if response.statusCode == 207 {
                           return self.checkWhetherReturns404ForMissingFile(url: url)
                                      .flatMap({ self.checkWritability(url: url) })
                       }

                       if response.statusCode == 404 {
                           // Zotero directory wasn't found, see if parent directory exists
                           return self.propFind(url: url.deletingLastPathComponent())
                                      .flatMap({ response, _ -> Observable<()> in
                                          if response.statusCode == 207 {
                                              return Observable.error(Error.zoteroDirNotFound)
                                          } else {
                                              return Observable.error(Error.parentDirNotFound)
                                          }
                                      })
                       }

                       return Observable.just(())
                   })
                   .asSingle()
                   .flatMap({ _ in Single.just(url) })
    }

    private func checkWritability(url: URL) -> Observable<()> {
        return Observable.just(())
    }

    private func checkWhetherReturns404ForMissingFile(url: URL) -> Observable<()> {
        var request = URLRequest(url: url.appendingPathComponent("nonexistent.prop"))
        request.httpMethod = "GET"
        return self.urlSession.rx.response(request: request)
                   .validate(successCodeCheck: { return $0 == 404 || (200..<300).contains($0) })
                   .flatMap({ response, _ -> Observable<()> in
                       if response.statusCode == 404 {
                           return Observable.just(())
                       } else {
                           return Observable.error(Error.nonExistentFileNotMissing)
                       }
                   })
    }

    private func propFind(url: URL) -> Observable<(response: HTTPURLResponse, data: Data)> {
        // IIS 5.1 requires at least one property in PROPFIND
        let xml = "<propfind xmlns='DAV:'><prop><getcontentlength/></prop></propfind>"
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("0", forHTTPHeaderField: "Depth")
        request.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = xml.data(using: .utf8)

        return self.urlSession.rx.response(request: request)
                   .validate(successCodes: [207, 404])
    }

    private func createUrl() -> Single<URL> {
        return Single.create { [weak self] subscriber in
            guard let `self` = self else {
                subscriber(.failure(Error.expired))
                return Disposables.create()
            }

            guard let scheme = self.sessionStorage.scheme else {
                DDLogError("WebDavController: scheme not found")
                subscriber(.failure(Error.noScheme))
                return Disposables.create()
            }
            guard scheme == "http" || scheme == "https" else {
                DDLogError("WebDavController: scheme invalid (\(scheme))")
                subscriber(.failure(Error.schemeInvalid))
                return Disposables.create()
            }
            guard let username = self.sessionStorage.username, !username.isEmpty else {
                DDLogError("WebDavController: username not found")
                subscriber(.failure(Error.noUsername))
                return Disposables.create()
            }
            guard let password = self.sessionStorage.password, !password.isEmpty else {
                DDLogError("WebDavController: username not found")
                subscriber(.failure(Error.noPassword))
                return Disposables.create()
            }
            guard let url = self.sessionStorage.url, !url.isEmpty else {
                DDLogError("WebDavController: url not found")
                subscriber(.failure(Error.noUrl))
                return Disposables.create()
            }

            let urlComponents = url.components(separatedBy: "/")
            guard !urlComponents.isEmpty else {
                DDLogError("WebDavController: url components empty - \(url)")
                subscriber(.failure(Error.invalidUrl))
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
            components.scheme = scheme
            components.user = username
            components.password = password
            components.host = host
            components.path = path
            components.port = port

            if let url = components.url {
                subscriber(.success(url))
            } else {
                subscriber(.failure(Error.invalidUrl))
            }

            return Disposables.create()
        }
    }
}

extension ObservableType where Element == (response: HTTPURLResponse, data: Data) {
    fileprivate func validate(successCodes: Set<Int>) -> Observable<Element> {
        return self.flatMap { response, data -> Observable<Element> in
            if successCodes.contains(response.statusCode) {
                return Observable.just((response, data))
            } else {
                return Observable.error(WebDavController.Error.unknownResponse(code: response.statusCode, url: response.url?.absoluteString ?? ""))
            }
        }
    }

    fileprivate func validate(successCodeCheck: @escaping (Int) -> Bool) -> Observable<Element> {
        return self.flatMap { response, data -> Observable<Element> in
            if successCodeCheck(response.statusCode) {
                return Observable.just((response, data))
            } else {
                return Observable.error(WebDavController.Error.unknownResponse(code: response.statusCode, url: response.url?.absoluteString ?? ""))
            }
        }
    }
}
