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
    override class func spec() {
        describe("a WebDAV controller") {
            func testCheckServer(with credentials: WebDavSessionStorage, successAction: @escaping () -> Void, errorAction: @escaping (Error) -> Void) {
                webDavController = WebDavControllerImpl(dbStorage: dbStorage, fileStorage: TestControllers.fileStorage, sessionStorage: credentials)
                webDavController.checkServer(queue: .main)
                    .observe(on: MainScheduler.instance)
                    .subscribe(onSuccess: { _ in
                        successAction()
                    }, onFailure: { error in
                        errorAction(error)
                    })
                    .disposed(by: disposeBag)
            }
            
            func testDownload(attachment: Attachment, successAction: @escaping () -> Void, errorAction: @escaping (Error) -> Void) {
                webDavController = WebDavControllerImpl(dbStorage: dbStorage, fileStorage: TestControllers.fileStorage, sessionStorage: verifiedCredentials)
                downloader = AttachmentDownloader(
                    userId: userId,
                    apiClient: TestControllers.apiClient,
                    fileStorage: TestControllers.fileStorage,
                    dbStorage: dbStorage,
                    webDavController: webDavController
                )

                downloader.observable
                    .subscribe(onNext: { update in
                        switch update.kind {
                        case .failed(let error):
                            errorAction(error)

                        case .ready:
                            successAction()
                        default: break
                        }
                    })
                    .disposed(by: disposeBag)

                downloader.downloadIfNeeded(attachment: attachment, parentKey: nil)
            }

            func testSync(syncFinishedAction: @escaping () -> Void) {
                webDavController = WebDavControllerImpl(dbStorage: dbStorage, fileStorage: TestControllers.fileStorage, sessionStorage: verifiedCredentials)
                backgroundUploaderContext = BackgroundUploaderContext()
                let attachmentDownloader = AttachmentDownloader(
                    userId: userId,
                    apiClient: TestControllers.apiClient,
                    fileStorage: TestControllers.fileStorage,
                    dbStorage: dbStorage,
                    webDavController: webDavController
                )
                syncController = SyncController(
                    userId: userId,
                    apiClient: TestControllers.apiClient,
                    dbStorage: dbStorage,
                    fileStorage: TestControllers.fileStorage,
                    schemaController: TestControllers.schemaController,
                    dateParser: TestControllers.dateParser,
                    backgroundUploaderContext: backgroundUploaderContext,
                    webDavController: webDavController,
                    attachmentDownloader: attachmentDownloader,
                    syncDelayIntervals: [0, 1, 2, 3],
                    maxRetryCount: 4
                )
                syncController.set(coordinator: TestConflictCoordinator(createZoteroDirectory: false))

                syncController.reportFinish = { _ in
                    inMainThread {
                        syncFinishedAction()
                    }
                }

                syncController.start(type: .normal, libraries: .all, retryAttempt: 0)
            }
            
            let userId = 100
            let unverifiedCredentials = WebDavCredentials(isEnabled: true, username: "user", password: "password", scheme: .http, url: "127.0.0.1:9999", isVerified: false)
            let verifiedCredentials = WebDavCredentials(isEnabled: true, username: "user", password: "password", scheme: .http, url: "127.0.0.1:9999", isVerified: true)
            let webDavUrl = URL(string: "http://user:password@127.0.0.1:9999/zotero/")!
            let apiBaseUrl = URL(string: ApiConstants.baseUrlString)!
            var disposeBag: DisposeBag!
            // We need to retain realm with memory identifier so that data are not deleted
            var realm: Realm!
            var dbStorage: DbStorage!
            var webDavController: WebDavController!
            var downloader: AttachmentDownloader!
            var syncController: SyncController!
            var backgroundUploaderContext: BackgroundUploaderContext!
            
            beforeEach {
                let config = Realm.Configuration(inMemoryIdentifier: UUID().uuidString)
                dbStorage = RealmDbStorage(config: config)
                realm = try! Realm(configuration: config)
                webDavController = nil
                downloader = nil
                syncController = nil
                backgroundUploaderContext = nil
                disposeBag = DisposeBag()
                HTTPStubs.removeAllStubs()
            }
            
            context("Verify Server") {
                it("should show an error for a connection error") {
                    waitUntil(timeout: .seconds(10)) { finished in
                        testCheckServer(with: unverifiedCredentials) {
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
                    createStub(for: WebDavCheckRequest(url: webDavUrl), baseUrl: apiBaseUrl, statusCode: 403, jsonResponse: [] as [String])
                    
                    waitUntil(timeout: .seconds(10)) { finished in
                        testCheckServer(with: unverifiedCredentials) {
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
                    createStub(for: WebDavCheckRequest(url: webDavUrl), baseUrl: apiBaseUrl, headers: ["DAV": "1"], statusCode: 200, jsonResponse: [] as [String])
                    createStub(for: WebDavPropfindRequest(url: webDavUrl), ignoreBody: true, baseUrl: apiBaseUrl, statusCode: 404, jsonResponse: [] as [String])
                    createStub(for: WebDavPropfindRequest(url: webDavUrl.deletingLastPathComponent()), ignoreBody: true, baseUrl: apiBaseUrl, statusCode: 404, jsonResponse: [] as [String])
                    
                    waitUntil(timeout: .seconds(10)) { finished in
                        testCheckServer(with: unverifiedCredentials) {
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
                    createStub(for: WebDavCheckRequest(url: webDavUrl), baseUrl: apiBaseUrl, headers: ["DAV": "1"], statusCode: 200, jsonResponse: [] as [String])
                    createStub(for: WebDavPropfindRequest(url: webDavUrl), ignoreBody: true, baseUrl: apiBaseUrl, statusCode: 207, jsonResponse: [] as [String])
                    createStub(for: WebDavNonexistentPropRequest(url: webDavUrl), ignoreBody: true, baseUrl: apiBaseUrl, statusCode: 200, jsonResponse: [] as [String])
                    
                    waitUntil(timeout: .seconds(10)) { finished in
                        testCheckServer(with: unverifiedCredentials) {
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
            
            context("Download") {
                it("handles missing zip") {
                    let filename = "test"
                    let contentType = "application/pdf"
                    let attachment = Attachment(
                        type: .file(filename: filename, contentType: contentType, location: .remote, linkType: .importedUrl),
                        title: "Test",
                        key: "aaaaaa",
                        libraryId: .custom(.myLibrary)
                    )
                    let file = Files.attachmentFile(in: attachment.libraryId, key: attachment.key, filename: filename, contentType: contentType)
                    let request = FileRequest(webDavUrl: webDavUrl.appendingPathComponent(attachment.key + ".zip"), destination: file)
                    
                    createStub(for: request, baseUrl: apiBaseUrl, responseError: AFError.responseValidationFailed(reason: .unacceptableStatusCode(code: 404)))
                    
                    waitUntil(timeout: .seconds(10)) { finished in
                        testDownload(attachment: attachment, successAction: {
                            fail("Succeeded to download missing file")
                            finished()
                        }, errorAction: { _ in
                            finished()
                        })
                    }
                }
                
                it("downloads zip and unzips file") {
                    let filename = "bitcoin"
                    let contentType = "application/pdf"
                    let zipUrl = URL(fileURLWithPath: Bundle(for: WebDavControllerSpec.self).path(forResource: "bitcoin", ofType: "zip")!)
                    let attachment = Attachment(
                        type: .file(filename: filename, contentType: contentType, location: .remote, linkType: .importedUrl),
                        title: "Test",
                        key: "AAAAAA",
                        libraryId: .custom(.myLibrary)
                    )
                    let file = Files.attachmentFile(in: attachment.libraryId, key: attachment.key, filename: filename, contentType: contentType)
                    let request = FileRequest(webDavUrl: webDavUrl.appendingPathComponent(attachment.key + ".zip"), destination: file)
                    
                    createStub(for: request, ignoreBody: true, baseUrl: apiBaseUrl, headers: ["Zotero-File-Compressed": "Yes"], statusCode: 200, url: zipUrl)
                    
                    waitUntil(timeout: .seconds(10)) { finished in
                        testDownload(attachment: attachment, successAction: {
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
            
            context("Syncing") {
                it("Uploads new files to WebDAV") {
                    let libraryId = LibraryIdentifier.custom(.myLibrary)
                    let itemKey = "AAAAAA"
                    let filename = "test"
                    let contentType = "application/pdf"
                    let oldVersion = 2
                    let newVersion = 3
                    
                    // Setup DB state
                    try! realm.write {
                        let myLibrary = RCustomLibrary()
                        myLibrary.type = .myLibrary
                        realm.add(myLibrary)
                        
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
                        
                        realm.add(item)
                    }
                    
                    var pdfData = "test".data(using: .utf8)!
                    pdfData.insert(contentsOf: [0x25, 0x50, 0x44, 0x46], at: 0)
                    
                    let file = Files.attachmentFile(in: libraryId, key: itemKey, filename: filename, contentType: contentType)
                    try! TestControllers.fileStorage.write(pdfData, to: file, options: .atomic)
                    
                    createStub(for: KeyRequest(), baseUrl: apiBaseUrl, url: Bundle(for: Self.self).url(forResource: "test_keys", withExtension: "json")!)
                    createStub(for: GroupVersionsRequest(userId: userId), baseUrl: apiBaseUrl, headers: ["last-modified-version": "\(oldVersion)"], jsonResponse: [:] as [String: Any])
                    createStub(
                        for: WebDavDownloadRequest(url: webDavUrl.appendingPathComponent(itemKey + ".prop")),
                        ignoreBody: true,
                        baseUrl: webDavUrl,
                        statusCode: 200,
                        xmlResponse: "<properties version=\"1\"><mtime>2</mtime><hash>bbbb</hash></properties>"
                    )
                    createStub(
                        for: WebDavDeleteRequest(url: webDavUrl.appendingPathComponent(itemKey + ".prop")),
                        ignoreBody: true,
                        baseUrl: webDavUrl,
                        statusCode: 200,
                        jsonResponse: [] as [String]
                    )
                    createStub(
                        for: WebDavWriteRequest(url: webDavUrl.appendingPathComponent(itemKey + ".prop"), data: Data()),
                        ignoreBody: true,
                        baseUrl: webDavUrl,
                        statusCode: 200,
                        jsonResponse: [] as [String]
                    )
                    createStub(
                        for: AttachmentUploadRequest(endpoint: .webDav(webDavUrl.appendingPathComponent(itemKey + ".zip")), httpMethod: .put),
                        ignoreBody: true,
                        baseUrl: webDavUrl,
                        statusCode: 200,
                        jsonResponse: [] as [String]
                    )
                    
                    let updatesRequest = UpdatesRequest(libraryId: libraryId, userId: userId, objectType: .item, params: [], version: nil)
                    stub(condition: updatesRequest.stubCondition(with: apiBaseUrl, ignoreBody: true), response: { request -> HTTPStubsResponse in
                        if request.allHTTPHeaderFields?["If-Unmodified-Since-Version"] != nil {
                            // First request to submit a new item
                            let itemJson = attachmentItemJson(key: itemKey, version: newVersion, filename: filename, contentType: contentType)
                            return HTTPStubsResponse(
                                jsonObject: ["success": ["0": itemKey] as [String: Any], "successful": ["0": itemJson], "unchanged": [:], "failed": [:]],
                                statusCode: 200,
                                headers: ["last-modified-version": "\(newVersion)"]
                            )
                        } else {
                            // Second request to submit new mtime and hash
                            let itemJson = attachmentItemJson(key: itemKey, version: newVersion + 1, filename: filename, contentType: contentType)
                            return HTTPStubsResponse(
                                jsonObject: ["success": ["0": itemKey] as [String: Any], "successful": ["0": itemJson], "unchanged": [:], "failed": [:]],
                                statusCode: 200,
                                headers: ["last-modified-version": "\(newVersion + 1)"]
                            )
                        }
                    })
                    
                    waitUntil(timeout: .seconds(10)) { doneAction in
                        testSync {
                            let item = try! dbStorage.perform(request: ReadItemDbRequest(libraryId: libraryId, key: itemKey), on: .main)
                            
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
                    let md5 = "abcdef"
                    
                    let itemJson = attachmentItemJson(key: itemKey, version: 2, filename: filename, contentType: contentType)
                    
                    // Setup DB state
                    try! realm.write {
                        let myLibrary = RCustomLibrary()
                        myLibrary.type = .myLibrary
                        realm.add(myLibrary)
                        
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
                        field4.value = md5
                        field4.changed = true
                        item.fields.append(field4)
                        
                        let field5 = RItemField()
                        field5.key = FieldKeys.Item.Attachment.linkMode
                        field5.value = LinkMode.importedFile.rawValue
                        field5.changed = true
                        item.fields.append(field5)
                        
                        realm.add(item)
                    }
                    
                    var pdfData = "test".data(using: .utf8)!
                    pdfData.insert(contentsOf: [0x25, 0x50, 0x44, 0x46], at: 0)
                    
                    let file = Files.attachmentFile(in: libraryId, key: itemKey, filename: filename, contentType: contentType)
                    try! TestControllers.fileStorage.write(pdfData, to: file, options: .atomic)
                    
                    createStub(for: KeyRequest(), baseUrl: apiBaseUrl, url: Bundle(for: Self.self).url(forResource: "test_keys", withExtension: "json")!)
                    createStub(for: GroupVersionsRequest(userId: userId), baseUrl: apiBaseUrl, headers: ["last-modified-version": "\(oldVersion)"], jsonResponse: [:] as [String: Any])
                    createStub(
                        for: WebDavDownloadRequest(url: webDavUrl.appendingPathComponent(itemKey + ".prop")),
                        ignoreBody: true,
                        baseUrl: apiBaseUrl,
                        statusCode: 200,
                        xmlResponse: "<properties version=\"1\"><mtime>2</mtime><hash>\(md5)</hash></properties>"
                    )
                    createStub(
                        for: UpdatesRequest(libraryId: libraryId, userId: userId, objectType: .item, params: [], version: nil),
                        ignoreBody: true,
                        baseUrl: apiBaseUrl,
                        headers: ["last-modified-version": "\(newVersion)"],
                        statusCode: 200,
                        jsonResponse: ["success": ["0": itemKey] as [String: Any], "successful": ["0": itemJson], "unchanged": [:], "failed": [:]]
                    )
                    
                    waitUntil(timeout: .seconds(10)) { doneAction in
                        testSync {
                            let item = try! dbStorage.perform(request: ReadItemDbRequest(libraryId: libraryId, key: itemKey), on: .main)
                            
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
                    let md5 = "abcdef"
                    
                    var itemJson = attachmentItemJson(key: itemKey, version: 2, filename: filename, contentType: contentType)
                    itemJson["version"] = newVersion
                    
                    // Setup DB state
                    try! realm.write {
                        let myLibrary = RCustomLibrary()
                        myLibrary.type = .myLibrary
                        realm.add(myLibrary)
                        
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
                        field4.value = md5
                        field4.changed = true
                        item.fields.append(field4)
                        
                        let field5 = RItemField()
                        field5.key = FieldKeys.Item.Attachment.linkMode
                        field5.value = LinkMode.importedFile.rawValue
                        field5.changed = true
                        item.fields.append(field5)
                        
                        realm.add(item)
                    }
                    
                    var pdfData = "test".data(using: .utf8)!
                    pdfData.insert(contentsOf: [0x25, 0x50, 0x44, 0x46], at: 0)
                    
                    let file = Files.attachmentFile(in: libraryId, key: itemKey, filename: filename, contentType: contentType)
                    try! TestControllers.fileStorage.write(pdfData, to: file, options: .atomic)
                    
                    createStub(for: KeyRequest(), baseUrl: apiBaseUrl, url: Bundle(for: Self.self).url(forResource: "test_keys", withExtension: "json")!)
                    createStub(for: GroupVersionsRequest(userId: userId), baseUrl: apiBaseUrl, headers: ["last-modified-version": "\(oldVersion)"], jsonResponse: [:] as [String: Any])
                    createStub(
                        for: UpdatesRequest(libraryId: libraryId, userId: userId, objectType: .item, params: [], version: oldVersion),
                        ignoreBody: true,
                        baseUrl: apiBaseUrl,
                        headers: ["last-modified-version": "\(newVersion)"],
                        statusCode: 200,
                        jsonResponse: ["success": ["0": itemKey] as [String: Any], "successful": ["0": itemJson], "unchanged": [:], "failed": [:]]
                    )
                    createStub(
                        for: WebDavDownloadRequest(url: webDavUrl.appendingPathComponent(itemKey + ".prop")),
                        ignoreBody: true,
                        baseUrl: webDavUrl,
                        statusCode: 200,
                        xmlResponse: "<properties version=\"1\"><mtime>1</mtime><hash>\(md5)</hash></properties>"
                    )
                    
                    waitUntil(timeout: .seconds(10)) { doneAction in
                        testSync {
                            let item = try! dbStorage.perform(request: ReadItemDbRequest(libraryId: libraryId, key: itemKey), on: .main)
                            
                            expect(item.attachmentNeedsSync).to(beFalse())
                            expect(item.version).to(equal(newVersion))
                            
                            doneAction()
                        }
                    }
                }
                
                it("Removes files from WebDAV after submission of local deletions to Zotero API") {
                    let header = ["last-modified-version": "1"]
                    let libraryId = LibraryIdentifier.custom(.myLibrary)
                    let itemKey = "AAAAAA"
                    let itemKey2 = "BBBBBB"
                    let itemKey3 = "CCCCCC"
                    
                    // Setup DB state
                    try! realm.write {
                        let myLibrary = RCustomLibrary()
                        myLibrary.type = .myLibrary
                        realm.add(myLibrary)
                        
                        let versions = RVersions()
                        myLibrary.versions = versions
                        
                        let item = RItem()
                        item.key = itemKey
                        item.rawType = ItemTypes.attachment
                        item.baseTitle = "Deleted attachment"
                        item.deleted = true
                        item.libraryId = .custom(.myLibrary)
                        realm.add(item)
                        
                        let item2 = RItem()
                        item2.key = itemKey3
                        item2.rawType = ItemTypes.webpage
                        item2.baseTitle = "Deleted webpage"
                        item2.deleted = true
                        item2.libraryId = .custom(.myLibrary)
                        realm.add(item2)
                        
                        let item3 = RItem()
                        item3.key = itemKey2
                        item3.rawType = ItemTypes.attachment
                        item3.baseTitle = "Deleted webpage attachment"
                        item3.libraryId = .custom(.myLibrary)
                        realm.add(item3)
                        
                        item3.parent = item2
                    }
                    
                    var deletionCount = 0
                    
                    createStub(for: KeyRequest(), baseUrl: apiBaseUrl, url: Bundle(for: Self.self).url(forResource: "test_keys", withExtension: "json")!)
                    createStub(for: GroupVersionsRequest(userId: userId), baseUrl: apiBaseUrl, headers: header, jsonResponse: [:] as [String: Any])
                    createStub(
                        for: SubmitDeletionsRequest(libraryId: libraryId, userId: userId, objectType: .item, keys: [itemKey, itemKey3], version: 0),
                        baseUrl: apiBaseUrl,
                        headers: header,
                        jsonResponse: [:] as [String: Any]
                    )
                    createStub(
                        for: WebDavDeleteRequest(url: webDavUrl.appendingPathComponent(itemKey + ".prop")),
                        ignoreBody: true,
                        baseUrl: apiBaseUrl,
                        statusCode: 200,
                        jsonResponse: [:] as [String: Any],
                        responseAction: {
                            deletionCount += 1
                        }
                    )
                    createStub(
                        for: WebDavDeleteRequest(url: webDavUrl.appendingPathComponent(itemKey + ".zip")),
                        ignoreBody: true,
                        baseUrl: apiBaseUrl,
                        statusCode: 200,
                        jsonResponse: [:] as [String: Any],
                        responseAction: {
                            deletionCount += 1
                        }
                    )
                    createStub(
                        for: WebDavDeleteRequest(url: webDavUrl.appendingPathComponent(itemKey2 + ".prop")),
                        ignoreBody: true,
                        baseUrl: apiBaseUrl,
                        statusCode: 200,
                        jsonResponse: [:] as [String: Any],
                        responseAction: {
                            deletionCount += 1
                        }
                    )
                    createStub(
                        for: WebDavDeleteRequest(url: webDavUrl.appendingPathComponent(itemKey2 + ".zip")),
                        ignoreBody: true,
                        baseUrl: apiBaseUrl,
                        statusCode: 200,
                        jsonResponse: [:] as [String: Any],
                        responseAction: {
                            deletionCount += 1
                        }
                    )
                    
                    waitUntil(timeout: .seconds(10)) { doneAction in
                        testSync {
                            expect(deletionCount).to(equal(4))
                            
                            let count = (try? dbStorage.perform(request: ReadWebDavDeletionsDbRequest(libraryId: .custom(.myLibrary)), on: .main))?.count ?? -1
                            expect(count).to(equal(0))
                            
                            doneAction()
                        }
                    }
                }
            }
        }
    }

    private class func attachmentItemJson(key: String, version: Int, filename: String, contentType: String) -> [String: Any] {
        let itemUrl = Bundle(for: Self.self).url(forResource: "test_item_attachment", withExtension: "json")!
        var itemJson = (try! JSONSerialization.jsonObject(with: (try! Data(contentsOf: itemUrl)), options: .allowFragments)) as! [String: Any]
        itemJson["key"] = key
        itemJson["version"] = version
        var itemData = itemJson["data"] as! [String: Any]
        itemData["filename"] = filename
        itemData["contentType"] = contentType
        itemJson["data"] = itemData
        return itemJson
    }
}
