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
    private let userId = 100
    private let unverifiedCredentials = WebDavCredentials(isEnabled: true, username: "user", password: "password", scheme: .http, url: "127.0.0.1:9999", isVerified: false)
    private let verifiedCredentials = WebDavCredentials(isEnabled: true, username: "user", password: "password", scheme: .http, url: "127.0.0.1:9999", isVerified: true)
    private let webDavUrl = URL(string: "http://user:password@127.0.0.1:9999/zotero/")!
    private let apiBaseUrl = URL(string: ApiConstants.baseUrlString)!
    private var webDavController: WebDavController?
    private var downloader: AttachmentDownloader?
    private var disposeBag: DisposeBag = DisposeBag()
    private var syncController: SyncController?
    // We need to retain realm with memory identifier so that data are not deleted
    private var realm: Realm!
    private var dbStorage: DbStorage!

    override func spec() {
        beforeEach {
            let config = Realm.Configuration(inMemoryIdentifier: UUID().uuidString)
            self.dbStorage = RealmDbStorage(config: config)
            self.realm = try! Realm(configuration: config)
            self.webDavController = nil
            self.downloader = nil
            self.syncController = nil
            self.disposeBag = DisposeBag()
            HTTPStubs.removeAllStubs()
        }

        describe("Verify Server") {
            it("should show an error for a connection error") {
                waitUntil(timeout: .seconds(10)) { finished in
                    self.testCheckServer(with: self.unverifiedCredentials) {
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
                createStub(for: WebDavCheckRequest(url: self.webDavUrl), baseUrl: self.apiBaseUrl, statusCode: 403, jsonResponse: [])

                waitUntil(timeout: .seconds(10)) { finished in
                    self.testCheckServer(with: self.unverifiedCredentials) {
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
                createStub(for: WebDavCheckRequest(url: self.webDavUrl), baseUrl: self.apiBaseUrl, headers: ["DAV": "1"], statusCode: 200, jsonResponse: [])
                createStub(for: WebDavPropfindRequest(url: self.webDavUrl), ignoreBody: true, baseUrl: self.apiBaseUrl, statusCode: 404, jsonResponse: [])
                createStub(for: WebDavPropfindRequest(url: self.webDavUrl.deletingLastPathComponent()), ignoreBody: true, baseUrl: self.apiBaseUrl, statusCode: 404, jsonResponse: [])

                waitUntil(timeout: .seconds(10)) { finished in
                    self.testCheckServer(with: self.unverifiedCredentials) {
                        fail("Succeeded with unreachable server")
                        finished()
                    } errorAction: { error in
                        if let error = error as? WebDavError.Verification, case .parentDirNotFound = error {
                            finished()
                            return
                        }

                        fail("Unknown error received - \(error)")
                        finished()
                    }
                }
            }

            it("should show an error for a 200 for a nonexistent file") {
                createStub(for: WebDavCheckRequest(url: self.webDavUrl), baseUrl: self.apiBaseUrl, headers: ["DAV": "1"], statusCode: 200, jsonResponse: [])
                createStub(for: WebDavPropfindRequest(url: self.webDavUrl), ignoreBody: true, baseUrl: self.apiBaseUrl, statusCode: 207, jsonResponse: [])
                createStub(for: WebDavNonexistentPropRequest(url: self.webDavUrl), ignoreBody: true, baseUrl: self.apiBaseUrl, statusCode: 200, jsonResponse: [])

                waitUntil(timeout: .seconds(10)) { finished in
                    self.testCheckServer(with: self.unverifiedCredentials) {
                        fail("Succeeded with unreachable server")
                        finished()
                    } errorAction: { error in
                        if let error = error as? WebDavError.Verification, case .nonExistentFileNotMissing = error {
                            finished()
                            return
                        }

                        fail("Unknown error received - \(error)")
                        finished()
                    }
                }
            }
        }

        describe("Download") {
            it("handles missing zip") {
                let filename = "test"
                let contentType = "application/pdf"
                let attachment = Attachment(type: .file(filename: filename, contentType: contentType, location: .remote, linkType: .importedUrl), title: "Test", key: "aaaaaa", libraryId: .custom(.myLibrary))
                let file = Files.attachmentFile(in: attachment.libraryId, key: attachment.key, filename: filename, contentType: contentType)
                let request = FileRequest(webDavUrl: self.webDavUrl.appendingPathComponent(attachment.key + ".zip"), destination: file)

                createStub(for: request, baseUrl: self.apiBaseUrl, responseError: AFError.responseValidationFailed(reason: .unacceptableStatusCode(code: 404)))

                waitUntil(timeout: .seconds(10)) { finished in
                    self.testDownload(attachment: attachment, successAction: {
                        fail("Succeeded to download missing file")
                        finished()
                    }, errorAction: { error in
                        finished()
                    })
                }
            }

            it("downloads zip and unzips file") {
                let filename = "bitcoin"
                let contentType = "application/pdf"
                let zipUrl = URL(fileURLWithPath: Bundle(for: WebDavControllerSpec.self).path(forResource: "bitcoin", ofType: "zip")!)
                let attachment = Attachment(type: .file(filename: filename, contentType: contentType, location: .remote, linkType: .importedUrl), title: "Test", key: "AAAAAA", libraryId: .custom(.myLibrary))
                let file = Files.attachmentFile(in: attachment.libraryId, key: attachment.key, filename: filename, contentType: contentType)
                let request = FileRequest(webDavUrl: self.webDavUrl.appendingPathComponent(attachment.key + ".zip"), destination: file)

                createStub(for: request, ignoreBody: true, baseUrl: self.apiBaseUrl, headers: ["Zotero-File-Compressed": "Yes"], statusCode: 200, url: zipUrl)

                waitUntil(timeout: .seconds(10)) { finished in
                    self.testDownload(attachment: attachment, successAction: {
                        let size = TestControllers.fileStorage.size(of: file)
                        expect(size).to(equal(184292))
                        try? TestControllers.fileStorage.remove(file.directory)
                        finished()
                    }, errorAction: { error in
                        fail("Could not download or unzip file - \(error)")
                        finished()
                    })
                }
            }
        }

        describe("Syncing") {
            it("Uploads new files to WebDAV") {
                let libraryId = LibraryIdentifier.custom(.myLibrary)
                let itemKey = "AAAAAA"
                let filename = "test"
                let contentType = "application/pdf"
                let oldVersion = 2
                let newVersion = 3

                // Setup DB state
                try! self.realm.write {
                    let myLibrary = RCustomLibrary()
                    myLibrary.type = .myLibrary
                    self.realm.add(myLibrary)

                    let versions = RVersions()
                    versions.items = oldVersion
                    myLibrary.versions = versions

                    let item = RItem()
                    item.key = itemKey
                    item.version = oldVersion
                    item.rawType = ItemTypes.attachment
                    item.libraryId = .custom(.myLibrary)
                    item.attachmentNeedsSync = true
                    let allChanges: RItemChanges = [.fields, .creators, .parent, .trash, .relations, .tags, .collections, .type]
                    item.changes.append(RObjectChange.create(changes: allChanges))

                    let field1 = RItemField()
                    field1.key = FieldKeys.Item.Attachment.contentType
                    field1.value = contentType
                    field1.changed = true
                    item.fields.append(field1)

                    let field2 = RItemField()
                    field2.key = FieldKeys.Item.Attachment.filename
                    field2.value = filename
                    field2.changed = true
                    item.fields.append(field2)

                    let field3 = RItemField()
                    field3.key = FieldKeys.Item.Attachment.mtime
                    field3.value = "1"
                    field3.changed = true
                    item.fields.append(field3)

                    let field4 = RItemField()
                    field4.key = FieldKeys.Item.Attachment.md5
                    field4.value = "aaaa"
                    field4.changed = true
                    item.fields.append(field4)

                    let field5 = RItemField()
                    field5.key = FieldKeys.Item.Attachment.linkMode
                    field5.value = LinkMode.importedFile.rawValue
                    field5.changed = true
                    item.fields.append(field5)

                    self.realm.add(item)
                }

                var pdfData = "test".data(using: .utf8)!
                pdfData.insert(contentsOf: [0x25, 0x50, 0x44, 0x46], at: 0)

                let file = Files.attachmentFile(in: libraryId, key: itemKey, filename: filename, contentType: contentType)
                try! TestControllers.fileStorage.write(pdfData, to: file, options: .atomic)

                createStub(for: KeyRequest(), baseUrl: self.apiBaseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys", withExtension: "json")!)
                createStub(for: GroupVersionsRequest(userId: self.userId), baseUrl: self.apiBaseUrl, headers: ["last-modified-version" : "\(oldVersion)"], jsonResponse: [:])
                createStub(for: WebDavDownloadRequest(url: self.webDavUrl.appendingPathComponent(itemKey + ".prop")), ignoreBody: true, baseUrl: self.apiBaseUrl, statusCode: 200,
                           xmlResponse: "<properties version=\"1\"><mtime>2</mtime><hash>bbbb</hash></properties>")
                createStub(for: WebDavDeleteRequest(url: self.webDavUrl.appendingPathComponent(itemKey + ".prop")), ignoreBody: true, baseUrl: self.apiBaseUrl, statusCode: 200, jsonResponse: [])
                createStub(for: WebDavWriteRequest(url: self.webDavUrl.appendingPathComponent(itemKey + ".prop"), data: Data()),
                           ignoreBody: true, baseUrl: self.apiBaseUrl, statusCode: 200, jsonResponse: [])
                createStub(for: AttachmentUploadRequest(endpoint: .webDav(self.webDavUrl.appendingPathComponent(itemKey + ".zip")), httpMethod: .put), ignoreBody: true, baseUrl: self.apiBaseUrl, statusCode: 200, jsonResponse: [])

                let updatesRequest = UpdatesRequest(libraryId: libraryId, userId: self.userId, objectType: .item, params: [], version: nil)
                stub(condition: updatesRequest.stubCondition(with: self.apiBaseUrl, ignoreBody: true), response: { request -> HTTPStubsResponse in
                    if request.allHTTPHeaderFields?["If-Unmodified-Since-Version"] != nil {
                        // First request to submit a new item
                        let itemJson = self.itemJson(key: itemKey, version: newVersion, type: "attachment")
                        return HTTPStubsResponse(jsonObject: ["success": ["0": itemKey], "successful": ["0": itemJson], "unchanged": [:], "failed": [:]], statusCode: 200, headers: ["last-modified-version" : "\(newVersion)"])
                    } else {
                        // Second request to submit new mtime and hash
                        let itemJson = self.itemJson(key: itemKey, version: newVersion + 1, type: "attachment")
                        return HTTPStubsResponse(jsonObject: ["success": ["0": itemKey], "successful": ["0": itemJson], "unchanged": [:], "failed": [:]], statusCode: 200, headers: ["last-modified-version" : "\(newVersion + 1)"])
                    }
                })

                waitUntil(timeout: .seconds(10)) { doneAction in
                    self.testSync {
                        let item = try! self.dbStorage.perform(request: ReadItemDbRequest(libraryId: libraryId, key: itemKey), on: .main)

                        expect(item.attachmentNeedsSync).to(beFalse())
                        expect(item.version).to(equal(newVersion + 1))

                        doneAction()
                    }
                }
            }

            it("Skips uploading but updates mtime if needed") {
                let libraryId = LibraryIdentifier.custom(.myLibrary)
                let itemKey = "AAAAAA"
                let filename = "test"
                let contentType = "application/pdf"
                let oldVersion = 2
                let newVersion = 3

                let itemJson = self.itemJson(key: itemKey, version: 2, type: "attachment")

                // Setup DB state
                try! self.realm.write {
                    let myLibrary = RCustomLibrary()
                    myLibrary.type = .myLibrary
                    self.realm.add(myLibrary)

                    let versions = RVersions()
                    versions.items = oldVersion
                    myLibrary.versions = versions

                    let item = RItem()
                    item.key = itemKey
                    item.version = oldVersion
                    item.rawType = ItemTypes.attachment
                    item.libraryId = .custom(.myLibrary)
                    item.attachmentNeedsSync = true
                    let allChanges: RItemChanges = [.fields, .creators, .parent, .trash, .relations, .tags, .collections, .type]
                    item.changes.append(RObjectChange.create(changes: allChanges))

                    let field1 = RItemField()
                    field1.key = FieldKeys.Item.Attachment.contentType
                    field1.value = contentType
                    field1.changed = true
                    item.fields.append(field1)

                    let field2 = RItemField()
                    field2.key = FieldKeys.Item.Attachment.filename
                    field2.value = filename
                    field2.changed = true
                    item.fields.append(field2)

                    let field3 = RItemField()
                    field3.key = FieldKeys.Item.Attachment.mtime
                    field3.value = "1"
                    field3.changed = true
                    item.fields.append(field3)

                    let field4 = RItemField()
                    field4.key = FieldKeys.Item.Attachment.md5
                    field4.value = "aaaa"
                    field4.changed = true
                    item.fields.append(field4)

                    let field5 = RItemField()
                    field5.key = FieldKeys.Item.Attachment.linkMode
                    field5.value = LinkMode.importedFile.rawValue
                    field5.changed = true
                    item.fields.append(field5)

                    self.realm.add(item)
                }

                var pdfData = "test".data(using: .utf8)!
                pdfData.insert(contentsOf: [0x25, 0x50, 0x44, 0x46], at: 0)

                let file = Files.attachmentFile(in: libraryId, key: itemKey, filename: filename, contentType: contentType)
                try! TestControllers.fileStorage.write(pdfData, to: file, options: .atomic)

                createStub(for: KeyRequest(), baseUrl: self.apiBaseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys", withExtension: "json")!)
                createStub(for: GroupVersionsRequest(userId: self.userId), baseUrl: self.apiBaseUrl, headers: ["last-modified-version" : "\(oldVersion)"], jsonResponse: [:])
                createStub(for: WebDavDownloadRequest(url: self.webDavUrl.appendingPathComponent(itemKey + ".prop")), ignoreBody: true, baseUrl: self.apiBaseUrl, statusCode: 200,
                           xmlResponse: "<properties version=\"1\"><mtime>2</mtime><hash>aaaa</hash></properties>")
                createStub(for: UpdatesRequest(libraryId: libraryId, userId: self.userId, objectType: .item, params: [], version: nil), ignoreBody: true, baseUrl: self.apiBaseUrl,
                           headers: ["last-modified-version" : "\(newVersion)"], statusCode: 200, jsonResponse: ["success": ["0": itemKey], "successful": ["0": itemJson], "unchanged": [:], "failed": [:]])

                waitUntil(timeout: .seconds(10)) { doneAction in
                    self.testSync {
                        let item = try! self.dbStorage.perform(request: ReadItemDbRequest(libraryId: libraryId, key: itemKey), on: .main)

                        expect(item.attachmentNeedsSync).to(beFalse())

                        let field = item.fields.filter(.key(FieldKeys.Item.Attachment.mtime)).first!
                        expect(field.value).to(equal("2"))
                        expect(field.changed).to(beTrue())

                        doneAction()
                    }
                }
            }

            it("Skips uploading existing files") {
                let libraryId = LibraryIdentifier.custom(.myLibrary)
                let itemKey = "AAAAAA"
                let filename = "test"
                let contentType = "application/pdf"
                let oldVersion = 2
                let newVersion = 3

                let itemJson = self.itemJson(key: itemKey, version: 2, type: "attachment")

                // Setup DB state
                try! self.realm.write {
                    let myLibrary = RCustomLibrary()
                    myLibrary.type = .myLibrary
                    self.realm.add(myLibrary)

                    let versions = RVersions()
                    versions.items = oldVersion
                    myLibrary.versions = versions

                    let item = RItem()
                    item.key = itemKey
                    item.version = oldVersion
                    item.rawType = ItemTypes.attachment
                    item.libraryId = .custom(.myLibrary)
                    item.attachmentNeedsSync = true
                    let allChanges: RItemChanges = [.fields, .creators, .parent, .trash, .relations, .tags, .collections, .type]
                    item.changes.append(RObjectChange.create(changes: allChanges))

                    let field1 = RItemField()
                    field1.key = FieldKeys.Item.Attachment.contentType
                    field1.value = contentType
                    field1.changed = true
                    item.fields.append(field1)

                    let field2 = RItemField()
                    field2.key = FieldKeys.Item.Attachment.filename
                    field2.value = filename
                    field2.changed = true
                    item.fields.append(field2)

                    let field3 = RItemField()
                    field3.key = FieldKeys.Item.Attachment.mtime
                    field3.value = "1"
                    field3.changed = true
                    item.fields.append(field3)

                    let field4 = RItemField()
                    field4.key = FieldKeys.Item.Attachment.md5
                    field4.value = "aaaa"
                    field4.changed = true
                    item.fields.append(field4)

                    let field5 = RItemField()
                    field5.key = FieldKeys.Item.Attachment.linkMode
                    field5.value = LinkMode.importedFile.rawValue
                    field5.changed = true
                    item.fields.append(field5)

                    self.realm.add(item)
                }

                var pdfData = "test".data(using: .utf8)!
                pdfData.insert(contentsOf: [0x25, 0x50, 0x44, 0x46], at: 0)

                let file = Files.attachmentFile(in: libraryId, key: itemKey, filename: filename, contentType: contentType)
                try! TestControllers.fileStorage.write(pdfData, to: file, options: .atomic)

                createStub(for: KeyRequest(), baseUrl: self.apiBaseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys", withExtension: "json")!)
                createStub(for: GroupVersionsRequest(userId: self.userId), baseUrl: self.apiBaseUrl, headers: ["last-modified-version" : "\(oldVersion)"], jsonResponse: [:])
                createStub(for: UpdatesRequest(libraryId: libraryId, userId: self.userId, objectType: .item, params: [], version: oldVersion),
                           ignoreBody: true, baseUrl: self.apiBaseUrl, headers: ["last-modified-version" : "\(newVersion)"], statusCode: 200,
                           jsonResponse: ["success": ["0": itemKey], "successful": ["0": itemJson], "unchanged": [:], "failed": [:]])
                createStub(for: WebDavDownloadRequest(url: self.webDavUrl.appendingPathComponent(itemKey + ".prop")), ignoreBody: true, baseUrl: self.apiBaseUrl, statusCode: 200,
                           xmlResponse: "<properties version=\"1\"><mtime>1</mtime><hash>aaaa</hash></properties>")

                waitUntil(timeout: .seconds(10)) { doneAction in
                    self.testSync {
                        let item = try! self.dbStorage.perform(request: ReadItemDbRequest(libraryId: libraryId, key: itemKey), on: .main)

                        expect(item.attachmentNeedsSync).to(beFalse())
                        expect(item.version).to(equal(newVersion))

                        doneAction()
                    }
                }
            }

            it("Removes files from WebDAV after submission of local deletions to Zotero API") {
                let header = ["last-modified-version" : "1"]
                let libraryId = LibraryIdentifier.custom(.myLibrary)
                let itemKey = "AAAAAA"
                let itemKey2 = "BBBBBB"
                let itemKey3 = "CCCCCC"

                // Setup DB state
                try! self.realm.write {
                    let myLibrary = RCustomLibrary()
                    myLibrary.type = .myLibrary
                    self.realm.add(myLibrary)

                    let versions = RVersions()
                    myLibrary.versions = versions

                    let item = RItem()
                    item.key = itemKey
                    item.rawType = ItemTypes.attachment
                    item.baseTitle = "Deleted attachment"
                    item.deleted = true
                    item.libraryId = .custom(.myLibrary)
                    self.realm.add(item)

                    let item2 = RItem()
                    item2.key = itemKey3
                    item2.rawType = ItemTypes.webpage
                    item2.baseTitle = "Deleted webpage"
                    item2.deleted = true
                    item2.libraryId = .custom(.myLibrary)
                    self.realm.add(item2)

                    let item3 = RItem()
                    item3.key = itemKey2
                    item3.rawType = ItemTypes.attachment
                    item3.baseTitle = "Deleted webpage attachment"
                    item3.libraryId = .custom(.myLibrary)
                    self.realm.add(item3)

                    item3.parent = item2
                }

                var deletionCount = 0

                createStub(for: KeyRequest(), baseUrl: self.apiBaseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys", withExtension: "json")!)
                createStub(for: GroupVersionsRequest(userId: self.userId), baseUrl: self.apiBaseUrl, headers: header, jsonResponse: [:])
                createStub(for: SubmitDeletionsRequest(libraryId: libraryId, userId: self.userId, objectType: .item, keys: [itemKey, itemKey3], version: 0),
                           baseUrl: self.apiBaseUrl, headers: header, jsonResponse: [:])
                createStub(for: WebDavDeleteRequest(url: self.webDavUrl.appendingPathComponent(itemKey + ".prop")), ignoreBody: true, baseUrl: self.apiBaseUrl, statusCode: 200, jsonResponse: [:],
                           responseAction: {
                    deletionCount += 1
                })
                createStub(for: WebDavDeleteRequest(url: self.webDavUrl.appendingPathComponent(itemKey + ".zip")), ignoreBody: true, baseUrl: self.apiBaseUrl, statusCode: 200, jsonResponse: [:],
                           responseAction: {
                    deletionCount += 1
                })
                createStub(for: WebDavDeleteRequest(url: self.webDavUrl.appendingPathComponent(itemKey2 + ".prop")), ignoreBody: true, baseUrl: self.apiBaseUrl, statusCode: 200, jsonResponse: [:],
                           responseAction: {
                    deletionCount += 1
                })
                createStub(for: WebDavDeleteRequest(url: self.webDavUrl.appendingPathComponent(itemKey2 + ".zip")), ignoreBody: true, baseUrl: self.apiBaseUrl, statusCode: 200, jsonResponse: [:],
                           responseAction: {
                    deletionCount += 1
                })

                waitUntil(timeout: .seconds(10)) { doneAction in
                    self.testSync {
                        expect(deletionCount).to(equal(4))

                        let count = (try? self.dbStorage.perform(request: ReadWebDavDeletionsDbRequest(libraryId: .custom(.myLibrary)), on: .main))?.count ?? -1
                        expect(count).to(equal(0))

                        doneAction()
                    }
                }
            }
        }
    }

    private func testCheckServer(with credentials: WebDavSessionStorage, successAction: @escaping () -> Void, errorAction: @escaping (Error) -> Void) {
        self.webDavController = WebDavControllerImpl(dbStorage: self.dbStorage, fileStorage: TestControllers.fileStorage, sessionStorage: credentials)
        self.webDavController!.checkServer(queue: .main)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { _ in
                successAction()
            }, onFailure: { error in
                errorAction(error)
            })
            .disposed(by: self.disposeBag)
    }

    private func testDownload(attachment: Attachment, successAction: @escaping () -> Void, errorAction: @escaping (Error) -> Void) {
        self.webDavController = WebDavControllerImpl(dbStorage: self.dbStorage, fileStorage: TestControllers.fileStorage, sessionStorage: self.verifiedCredentials)
        self.downloader = AttachmentDownloader(userId: self.userId, apiClient: TestControllers.apiClient, fileStorage: TestControllers.fileStorage, dbStorage: self.dbStorage, webDavController: self.webDavController!)

        self.downloader?.observable
            .subscribe(onNext: { update in
                switch update.kind {
                case .failed(let error):
                    errorAction(error)
                case .ready:
                    successAction()
                default: break
                }
            })
            .disposed(by: self.disposeBag)

        self.downloader?.downloadIfNeeded(attachment: attachment, parentKey: nil)
    }

    private func testSync(syncFinishedAction: @escaping () -> Void) {
        // Create webdav controller
        let webDavController = WebDavControllerImpl(dbStorage: self.dbStorage, fileStorage: TestControllers.fileStorage, sessionStorage: self.verifiedCredentials)
        // Create sync controller
        let syncController = SyncController(userId: self.userId, apiClient: TestControllers.apiClient, dbStorage: self.dbStorage, fileStorage: TestControllers.fileStorage,
                                            schemaController: TestControllers.schemaController, dateParser: TestControllers.dateParser, backgroundUploaderContext: BackgroundUploaderContext(),
                                            webDavController: webDavController, syncDelayIntervals: [0, 1, 2, 3], conflictDelays: [0, 1, 2, 3])
        syncController.set(coordinator: TestConflictCoordinator(createZoteroDirectory: false))

        self.syncController = syncController
        self.webDavController = webDavController

        self.syncController!.reportFinish = { _ in
            inMainThread {
                syncFinishedAction()
            }
        }

        self.syncController!.start(type: .normal, libraries: .all)
    }

    private func itemJson(key: String, version: Int, type: String) -> [String: Any] {
        let itemUrl = Bundle(for: WebDavControllerSpec.self).url(forResource: "test_item", withExtension: "json")!
        var itemJson = (try! JSONSerialization.jsonObject(with: (try! Data(contentsOf: itemUrl)), options: .allowFragments)) as! [String: Any]
        itemJson["key"] = key
        itemJson["version"] = version
        var itemData = itemJson["data"] as! [String: Any]
        itemData["itemType"] = type
        itemJson["data"] = itemData
        return itemJson
    }
}
