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
import RealmSwift
import RxSwift
import Quick

final class WebDavControllerSpec: QuickSpec {
    private let defaultCredentials = WebDavCredentials(username: "user", password: "password", scheme: .http, url: "127.0.0.1:9999", isVerified: false)
    private let defaultUrl = URL(string: "http://user:password@127.0.0.1:9999/zotero/")!
    private let baseUrl = URL(string: ApiConstants.baseUrlString)!
    private var webDavController: WebDavController?
    private var disposeBag: DisposeBag = DisposeBag()
    // We need to retain realm with memory identifier so that data are not deleted
    private var realm: Realm!
    private var dbStorage: DbStorage!

    override func spec() {
        beforeEach {
            let config = Realm.Configuration(inMemoryIdentifier: UUID().uuidString)
            self.dbStorage = RealmDbStorage(config: config)
            self.realm = try! Realm(configuration: config)
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
                createStub(for: WebDavCheckRequest(url: self.defaultUrl), baseUrl: self.baseUrl, statusCode: 403, jsonResponse: [])

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
                createStub(for: WebDavCheckRequest(url: self.defaultUrl), baseUrl: self.baseUrl, headers: ["DAV": "1"], statusCode: 200, jsonResponse: [])
                createStub(for: WebDavPropfindRequest(url: self.defaultUrl), ignoreBody: true, baseUrl: self.baseUrl, statusCode: 404, jsonResponse: [])
                createStub(for: WebDavPropfindRequest(url: self.defaultUrl.deletingLastPathComponent()), ignoreBody: true, baseUrl: self.baseUrl, statusCode: 404, jsonResponse: [])

                waitUntil(timeout: .seconds(10)) { finished in
                    self.test(with: self.defaultCredentials) {
                        fail("Succeeded with unreachable server")
                        finished()
                    } errorAction: { error in
                        if let error = error as? WebDavError.Verification, error == .parentDirNotFound {
                            finished()
                            return
                        }

                        fail("Unknown error received - \(error)")
                        finished()
                    }
                }
            }

            it("should show an error for a 200 for a nonexistent file") {
                createStub(for: WebDavCheckRequest(url: self.defaultUrl), baseUrl: self.baseUrl, headers: ["DAV": "1"], statusCode: 200, jsonResponse: [])
                createStub(for: WebDavPropfindRequest(url: self.defaultUrl), ignoreBody: true, baseUrl: self.baseUrl, statusCode: 207, jsonResponse: [])
                createStub(for: WebDavNonexistentPropRequest(url: self.defaultUrl), ignoreBody: true, baseUrl: self.baseUrl, statusCode: 200, jsonResponse: [])

                waitUntil(timeout: .seconds(10)) { finished in
                    self.test(with: self.defaultCredentials) {
                        fail("Succeeded with unreachable server")
                        finished()
                    } errorAction: { error in
                        if let error = error as? WebDavError.Verification, error == .nonExistentFileNotMissing {
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
        self.webDavController = WebDavControllerImpl(apiClient: TestControllers.apiClient, dbStorage: self.dbStorage, fileStorage: TestControllers.fileStorage, sessionStorage: credentials)
        self.webDavController!.checkServer(queue: .main)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { _ in
                successAction()
            }, onFailure: { error in
                errorAction(error)
            })
            .disposed(by: self.disposeBag)
    }
}
