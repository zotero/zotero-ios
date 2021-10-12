//
//  WebDavControllerSpec.swift
//  ZoteroTests
//
//  Created by Michal Rentka on 08.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//


@testable import Zotero

import Foundation

import Alamofire
import Nimble
import OHHTTPStubs
import OHHTTPStubsSwift
import RxSwift
import Quick

final class WebDavControllerSpec: QuickSpec {
    private let defaultCredentials = WebDavCredentials(username: "user", password: "password", scheme: .http, url: "127.0.0.1:9999")
    private let defaultUrl = URL(string: "http://user:password@127.0.0.1:9999/zotero/")!
    private let baseUrl = URL(string: ApiConstants.baseUrlString)!
    private var webDavController: WebDavController?
    private var disposeBag: DisposeBag = DisposeBag()

    override func spec() {
        beforeEach {
            self.webDavController = nil
            self.disposeBag = DisposeBag()
            HTTPStubs.removeAllStubs()
        }

        describe("Verify Server") {
            it("should show an error for a connection error") {
                waitUntil(timeout: .seconds(10)) { finished in
                    self.test(with: self.defaultCredentials) {
                        fail("Succeeded with unreachable server")
                        finished()
                    } errorAction: { error in
                        if let error = (error as? AFResponseError)?.error {
                            switch error {
                            case .sessionTaskFailed(let error):
                                let nsError = error as NSError
                                if nsError.code == NSURLErrorCannotConnectToHost {
                                    finished()
                                    return
                                }
                            default: break
                            }
                        }

                        fail("Unknown error received - \(error)")
                        finished()
                    }
                }
            }

            it("should show an error for a 403") {
                createStub(for: WebDavRequest(url: self.defaultUrl, httpMethod: .options, acceptableStatusCodes: []), baseUrl: self.baseUrl, statusCode: 403, jsonResponse: [])

                waitUntil(timeout: .seconds(10)) { finished in
                    self.test(with: self.defaultCredentials) {
                        fail("Succeeded with unreachable server")
                        finished()
                    } errorAction: { error in
                        if let statusCode = error.unacceptableStatusCode, statusCode == 403 {
                            finished()
                            return
                        }

                        fail("Unknown error received - \(error)")
                        finished()
                    }
                }
            }

            it("should show an error for a 404 for the parent directory") {
                createStub(for: WebDavRequest(url: self.defaultUrl, httpMethod: .options, acceptableStatusCodes: []), baseUrl: self.baseUrl, headers: ["DAV": "1"], statusCode: 200, jsonResponse: [])
                createStub(for: WebDavRequest(url: self.defaultUrl, httpMethod: .propfind, acceptableStatusCodes: []), ignoreBody: true, baseUrl: self.baseUrl, statusCode: 404, jsonResponse: [])
                createStub(for: WebDavRequest(url: self.defaultUrl.deletingLastPathComponent(), httpMethod: .propfind, acceptableStatusCodes: []),
                           ignoreBody: true, baseUrl: self.baseUrl, statusCode: 404, jsonResponse: [])

                waitUntil(timeout: .seconds(10)) { finished in
                    self.test(with: self.defaultCredentials) {
                        fail("Succeeded with unreachable server")
                        finished()
                    } errorAction: { error in
                        if let error = error as? WebDavController.Error.Verification, error == .parentDirNotFound {
                            finished()
                            return
                        }

                        fail("Unknown error received - \(error)")
                        finished()
                    }
                }
            }

            it("should show an error for a 200 for a nonexistent file") {
                createStub(for: WebDavRequest(url: self.defaultUrl, httpMethod: .options, acceptableStatusCodes: []), baseUrl: self.baseUrl, headers: ["DAV": "1"], statusCode: 200, jsonResponse: [])
                createStub(for: WebDavRequest(url: self.defaultUrl, httpMethod: .propfind, acceptableStatusCodes: []), ignoreBody: true, baseUrl: self.baseUrl, statusCode: 207, jsonResponse: [])
                createStub(for: WebDavRequest(url: self.defaultUrl.appendingPathComponent("nonexistent.prop"), httpMethod: .get, acceptableStatusCodes: []),
                           ignoreBody: true, baseUrl: self.baseUrl, statusCode: 200, jsonResponse: [])

                waitUntil(timeout: .seconds(10)) { finished in
                    self.test(with: self.defaultCredentials) {
                        fail("Succeeded with unreachable server")
                        finished()
                    } errorAction: { error in
                        if let error = error as? WebDavController.Error.Verification, error == .nonExistentFileNotMissing {
                            finished()
                            return
                        }

                        fail("Unknown error received - \(error)")
                        finished()
                    }
                }
            }
        }
    }

    private func test(with credentials: WebDavSessionStorage, successAction: @escaping () -> Void, errorAction: @escaping (Error) -> Void) {
        self.webDavController = WebDavController(apiClient: TestControllers.apiClient, sessionStorage: credentials)
        self.webDavController!.checkServer()
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: {
                successAction()
            }, onFailure: { error in
                errorAction(error)
            })
            .disposed(by: self.disposeBag)
    }
}

fileprivate class WebDavCredentials: WebDavSessionStorage {
    var isEnabled: Bool
    var username: String
    var url: String
    var scheme: WebDavScheme
    var password: String

    init(username: String, password: String, scheme: WebDavScheme, url: String) {
        self.isEnabled = true
        self.username = username
        self.password = password
        self.scheme = scheme
        self.url = url
    }
}
