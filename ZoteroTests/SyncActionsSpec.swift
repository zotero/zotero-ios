//
//  SyncActionsSpec.swift
//  ZoteroTests
//
//  Created by Michal Rentka on 09/07/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

@testable import Zotero

import Alamofire
import CocoaLumberjackSwift
import Nimble
import OHHTTPStubs
import OHHTTPStubsSwift
import RealmSwift
import RxSwift
import Quick

final class SyncActionsSpec: QuickSpec {
    private let userId = 100
    // We need to retain realm with memory identifier so that data are not deleted
    private let realm: Realm
    private let webDavController: WebDavController
    private let dbStorage: DbStorage
    private let disposeBag: DisposeBag

    required init() {
        let config = Realm.Configuration(inMemoryIdentifier: "TestsRealmConfig")
        self.realm = try! Realm(configuration: config)
        self.webDavController = WebDavTestController()
        self.dbStorage = RealmDbStorage(config: config)
        self.disposeBag = DisposeBag()
    }

    override func spec() {
        beforeSuite {
            Defaults.shared.webDavEnabled = false
        }

        beforeEach {
            try? TestControllers.fileStorage.remove(Files.downloads)

            HTTPStubs.removeAllStubs()

            try! self.realm.write {
                self.realm.deleteAll()
            }
        }

        describe("conflict resolution") {
            it("reverts group changes") {
                // Load urls for bundled files
                guard let collectionUrl = Bundle(for: type(of: self)).url(forResource: "test_collection", withExtension: "json"),
                      let itemUrl = Bundle(for: type(of: self)).url(forResource: "test_item", withExtension: "json"),
                      let searchUrl = Bundle(for: type(of: self)).url(forResource: "test_search", withExtension: "json") else {
                    fail("Could not find json files")
                    return
                }

                // Load their data
                let collectionData = try! Data(contentsOf: collectionUrl)
                let collectionJson = (try! JSONSerialization.jsonObject(with: collectionData, options: .allowFragments)) as! [String: Any]
                let searchData = try! Data(contentsOf: searchUrl)
                let searchJson = (try! JSONSerialization.jsonObject(with: searchData, options: .allowFragments)) as! [String: Any]
                let itemData = try! Data(contentsOf: itemUrl)
                let itemJson = (try! JSONSerialization.jsonObject(with: itemData, options: .allowFragments)) as! [String: Any]

                // Write original json files to directory folder for SyncActionHandler to use when reverting
                let collectionFile = Files.jsonCacheFile(for: .collection, libraryId: .group(1234123), key: "BBBBBBBB")
                try! FileManager.default.createMissingDirectories(for: collectionFile.createUrl().deletingLastPathComponent())
                try! collectionData.write(to: collectionFile.createUrl())
                let searchFile = Files.jsonCacheFile(for: .search, libraryId: .custom(.myLibrary), key: "CCCCCCCC")
                try! searchData.write(to: searchFile.createUrl())
                let itemFile = Files.jsonCacheFile(for: .item, libraryId: .custom(.myLibrary), key: "AAAAAAAA")
                try! itemData.write(to: itemFile.createUrl())

                // Create response models
                let collectionResponse = try! CollectionResponse(response: collectionJson)
                let searchResponse = try! SearchResponse(response: searchJson)
                let itemResponse = try! ItemResponse(response: itemJson, schemaController: TestControllers.schemaController)

                // Store original objects to db
                _ = try! self.dbStorage.perform(request: StoreItemsDbResponseRequest(responses: [itemResponse], schemaController: TestControllers.schemaController, dateParser: TestControllers.dateParser, preferResponseData: true), on: .main)
                try! self.dbStorage.perform(request: StoreCollectionsDbRequest(response: [collectionResponse]), on: .main)
                try! self.dbStorage.perform(request: StoreSearchesDbRequest(response: [searchResponse]), on: .main)

                // Change some objects so that they are updated locally
                try! self.dbStorage.perform(request: EditCollectionDbRequest(libraryId: .group(1234123), key: "BBBBBBBB", name: "New name", parentKey: nil), on: .main)
                let data = ItemDetailState.Data(title: "New title",
                                                type: "magazineArticle",
                                                isAttachment: false,
                                                localizedType: "Magazine Article",
                                                creators: [:],
                                                creatorIds: [],
                                                fields: [:],
                                                fieldIds: [],
                                                abstract: "New abstract",
                                                dateModified: Date(),
                                                dateAdded: Date())
                let snapshot = ItemDetailState.Data(title: "Bachelor thesis",
                                                type: "thesis",
                                                isAttachment: false,
                                                localizedType: "Thesis",
                                                creators: [:],
                                                creatorIds: [],
                                                fields: [:],
                                                fieldIds: [],
                                                abstract: "Some note",
                                                dateModified: Date(),
                                                dateAdded: Date())

                let changeRequest = EditItemFromDetailDbRequest(libraryId: .custom(.myLibrary), itemKey: "AAAAAAAA", data: data, snapshot: snapshot, schemaController: TestControllers.schemaController,
                                                                dateParser: TestControllers.dateParser)
                try! self.dbStorage.perform(request: changeRequest, on: .main)

                self.realm.refresh()

                let item = self.realm.objects(RItem.self).filter(.key("AAAAAAAA")).first
                expect(item?.rawType).to(equal("magazineArticle"))
                expect(item?.baseTitle).to(equal("New title"))
                expect(item?.fields.filter("key =  %@", FieldKeys.Item.abstract).first?.value).to(equal("New abstract"))
                expect(item?.isChanged).to(beTrue())

                let collection = self.realm.objects(RCollection.self).filter(.key("BBBBBBBB")).first
                expect(collection?.name).to(equal("New name"))
                expect(collection?.parentKey).to(beNil())

                waitUntil(timeout: .seconds(10), action: { doneAction in
                    RevertLibraryUpdatesSyncAction(libraryId: .custom(.myLibrary), dbStorage: self.dbStorage, fileStorage: TestControllers.fileStorage,
                                                   schemaController: TestControllers.schemaController, dateParser: TestControllers.dateParser, queue: .main).result
                                         .subscribe(onSuccess: { failures in
                                             expect(failures[.item]).to(beEmpty())
                                             expect(failures[.collection]).to(beEmpty())
                                             expect(failures[.search]).to(beEmpty())

                                             self.realm.refresh()

                                             let item = self.realm.objects(RItem.self).filter(.key("AAAAAAAA")).first
                                             expect(item?.rawType).to(equal("thesis"))
                                             expect(item?.baseTitle).to(equal("Bachelor thesis"))
                                             expect(item?.fields.filter("key =  %@", FieldKeys.Item.abstract).first?.value).to(equal("Some note"))
                                             expect(item?.changedFields.rawValue).to(equal(0))

                                             doneAction()
                                         }, onFailure: { error in
                                             fail("Could not revert user library: \(error)")
                                             doneAction()
                                         })
                                         .disposed(by: self.disposeBag)
                })

                waitUntil(timeout: .seconds(10), action: { doneAction in
                    RevertLibraryUpdatesSyncAction(libraryId: .group(1234123), dbStorage: self.dbStorage, fileStorage: TestControllers.fileStorage, schemaController: TestControllers.schemaController,
                                                   dateParser: TestControllers.dateParser, queue: .main).result
                                         .subscribe(onSuccess: { failures in
                                             expect(failures[.item]).to(beEmpty())
                                             expect(failures[.collection]).to(beEmpty())
                                             expect(failures[.search]).to(beEmpty())

                                             self.realm.refresh()

                                             let collection = self.realm.objects(RCollection.self).filter(.key("BBBBBBBB")).first
                                             expect(collection?.name).to(equal("Bachelor sources"))
                                             expect(collection?.parentKey).to(beNil())

                                             doneAction()
                                         }, onFailure: { error in
                                             fail("Could not revert group library: \(error)")
                                             doneAction()
                                         })
                                         .disposed(by: self.disposeBag)
                })
            }

            it("marks local changes as synced") {
                // Load urls for bundled files
                guard let collectionUrl = Bundle(for: type(of: self)).url(forResource: "test_collection", withExtension: "json"),
                      let itemUrl = Bundle(for: type(of: self)).url(forResource: "test_item", withExtension: "json") else {
                    fail("Could not find json files")
                    return
                }

                // Load their data
                let collectionData = try! Data(contentsOf: collectionUrl)
                let collectionJson = (try! JSONSerialization.jsonObject(with: collectionData, options: .allowFragments)) as! [String: Any]
                let itemData = try! Data(contentsOf: itemUrl)
                let itemJson = (try! JSONSerialization.jsonObject(with: itemData, options: .allowFragments)) as! [String: Any]

                // Create response models
                let collectionResponse = try! CollectionResponse(response: collectionJson)
                let itemResponse = try! ItemResponse(response: itemJson, schemaController: TestControllers.schemaController)

                // Store original objects to db
                _ = try! self.dbStorage.perform(request: StoreItemsDbResponseRequest(responses: [itemResponse], schemaController: TestControllers.schemaController,
                                                                                     dateParser: TestControllers.dateParser, preferResponseData: true), on: .main)
                try! self.dbStorage.perform(request: StoreCollectionsDbRequest(response: [collectionResponse]), on: .main)

                // Change some objects so that they are updated locally
                try! self.dbStorage.perform(request: EditCollectionDbRequest(libraryId: .group(1234123), key: "BBBBBBBB", name: "New name", parentKey: nil), on: .main)
                let data = ItemDetailState.Data(title: "New title",
                                                type: "magazineArticle",
                                                isAttachment: false,
                                                localizedType: "Magazine Article",
                                                creators: [:],
                                                creatorIds: [],
                                                fields: [:],
                                                fieldIds: [],
                                                abstract: "New abstract",
                                                dateModified: Date(),
                                                dateAdded: Date())
                let snapshot = ItemDetailState.Data(title: "Bachelor thesis",
                                                type: "thesis",
                                                isAttachment: false,
                                                localizedType: "Thesis",
                                                creators: [:],
                                                creatorIds: [],
                                                fields: [:],
                                                fieldIds: [],
                                                abstract: "Some note",
                                                dateModified: Date(),
                                                dateAdded: Date())
                let changeRequest = EditItemFromDetailDbRequest(libraryId: .custom(.myLibrary), itemKey: "AAAAAAAA", data: data, snapshot: snapshot, schemaController: TestControllers.schemaController,
                                                                dateParser: TestControllers.dateParser)
                try! self.dbStorage.perform(request: changeRequest, on: .main)

                self.realm.refresh()

                let item = self.realm.objects(RItem.self).filter(.key("AAAAAAAA")).first
                expect(item?.rawType).to(equal("magazineArticle"))
                expect(item?.baseTitle).to(equal("New title"))
                expect(item?.fields.filter("key =  %@", FieldKeys.Item.abstract).first?.value).to(equal("New abstract"))
                expect(item?.changedFields.rawValue).toNot(equal(0))
                expect(item?.isChanged).to(beTrue())

                let collection = self.realm.objects(RCollection.self).filter(.key("BBBBBBBB")).first
                expect(collection?.name).to(equal("New name"))
                expect(collection?.parentKey).to(beNil())
                expect(collection?.changedFields.rawValue).toNot(equal(0))

                waitUntil(timeout: .seconds(10), action: { doneAction in
                    MarkChangesAsResolvedSyncAction(libraryId: .custom(.myLibrary), dbStorage: self.dbStorage, queue: .main).result
                                         .subscribe(onSuccess: { _ in
                                             self.realm.refresh()

                                             let item = self.realm.objects(RItem.self).filter(.key("AAAAAAAA")).first
                                             expect(item?.rawType).to(equal("magazineArticle"))
                                             expect(item?.baseTitle).to(equal("New title"))
                                             expect(item?.fields.filter("key =  %@", FieldKeys.Item.abstract).first?.value).to(equal("New abstract"))
                                             expect(item?.changedFields.rawValue).to(equal(0))

                                             doneAction()
                                        }, onFailure: { error in
                                            fail("Could not sync user library: \(error)")
                                            doneAction()
                                        })
                                        .disposed(by: self.disposeBag)
                })

                waitUntil(timeout: .seconds(10), action: { doneAction in
                    MarkChangesAsResolvedSyncAction(libraryId: .group(1234123), dbStorage: self.dbStorage, queue: .main).result
                                         .subscribe(onSuccess: { _ in
                                             self.realm.refresh()

                                             let collection = self.realm.objects(RCollection.self).filter(.key("BBBBBBBB")).first
                                             expect(collection?.name).to(equal("New name"))
                                             expect(collection?.parentKey).to(beNil())
                                             expect(collection?.changedFields.rawValue).to(equal(0))

                                             doneAction()
                                         }, onFailure: { error in
                                             fail("Could not sync group library: \(error)")
                                             doneAction()
                                         })
                                         .disposed(by: self.disposeBag)
                })
            }
        }

        describe("attachment upload") {
            let baseUrl = URL(string: ApiConstants.baseUrlString)!

            it("fails when item metadata not submitted") {
                let key = "AAAAAAAA"
                let libraryId = LibraryIdentifier.group(1)
                let file = Files.attachmentFile(in: libraryId, key: key, filename: "file", contentType: "application/pdf")

                try! self.realm.write {
                    let library = RGroup()
                    library.identifier = 1
                    self.realm.add(library)

                    let item = RItem()
                    item.key = key
                    item.rawType = "attachment"
                    item.groupKey = library.identifier
                    let allChanges: RItemChanges = [.fields, .creators, .parent, .trash, .relations, .tags, .collections, .type]
                    item.changes.append(RObjectChange.create(changes: allChanges))
                    item.attachmentNeedsSync = true
                    self.realm.add(item)
                }

                waitUntil(timeout: .seconds(10), action: { doneAction in
                    UploadAttachmentSyncAction(key: key,
                                               file: file,
                                               filename: "doc.pdf",
                                               md5: "aaaaaaaa", mtime: 0,
                                               libraryId: libraryId,
                                               userId: self.userId,
                                               oldMd5: nil,
                                               apiClient: TestControllers.apiClient,
                                               dbStorage: self.dbStorage,
                                               fileStorage: TestControllers.fileStorage,
                                               webDavController: self.webDavController,
                                               schemaController: TestControllers.schemaController,
                                               dateParser: TestControllers.dateParser,
                                               queue: DispatchQueue.main,
                                               scheduler: MainScheduler.instance,
                                               disposeBag: self.disposeBag).result
                                         .subscribe(onSuccess: { _ in
                                             fail("Upload didn't fail with unsubmitted item")
                                             doneAction()
                                         }, onFailure: { error in
                                             if let handlerError = error as? SyncActionError {
                                                 expect(handlerError).to(equal(.attachmentItemNotSubmitted))
                                             } else {
                                                 fail("Unknown error: \(error.localizedDescription)")
                                             }
                                             doneAction()
                                         })
                                         .disposed(by: self.disposeBag)
                })
            }

            it("fails when file is not available") {
                let key = "AAAAAAAA"
                let filename = "doc.pdf"
                let libraryId = LibraryIdentifier.group(1)
                let file = Files.attachmentFile(in: libraryId, key: key, filename: filename, contentType: "application/pdf")

                try! self.realm.write {
                    let library = RGroup()
                    library.identifier = 1
                    self.realm.add(library)

                    let item = RItem()
                    item.key = key
                    item.rawType = "attachment"
                    item.groupKey = library.identifier
                    item.deleteAllChanges(database: self.realm)
                    item.attachmentNeedsSync = true
                    self.realm.add(item)
                }

                waitUntil(timeout: .seconds(10), action: { doneAction in
                    UploadAttachmentSyncAction(key: key,
                                               file: file,
                                               filename: filename,
                                               md5: "aaaaaaaa", mtime: 0,
                                               libraryId: libraryId,
                                               userId: self.userId,
                                               oldMd5: nil,
                                               apiClient: TestControllers.apiClient,
                                               dbStorage: self.dbStorage,
                                               fileStorage: TestControllers.fileStorage,
                                               webDavController: self.webDavController,
                                               schemaController: TestControllers.schemaController,
                                               dateParser: TestControllers.dateParser,
                                               queue: DispatchQueue.main,
                                               scheduler: MainScheduler.instance,
                                               disposeBag: self.disposeBag).result
                                         .subscribe(onSuccess: { _ in
                                             fail("Upload didn't fail with unsubmitted item")
                                             doneAction()
                                         }, onFailure: { error in
                                             if let handlerError = error as? SyncActionError {
                                                 expect(handlerError).to(equal(.attachmentMissing(key: key, libraryId: libraryId, title: "")))
                                             } else {
                                                 fail("Unknown error: \(error.localizedDescription)")
                                             }
                                             doneAction()
                                         })
                                         .disposed(by: self.disposeBag)
                })
            }

            it("it doesn't reupload when file is already uploaded") {
                let key = "AAAAAAAA"
                let filename = "doc.txt"
                let libraryId = LibraryIdentifier.group(1)
                let file = Files.attachmentFile(in: libraryId, key: key, filename: filename, contentType: "text/plain")

                let data = "test string".data(using: .utf8)!
                try! FileStorageController().write(data, to: file, options: .atomicWrite)
                let fileMd5 = md5(from: file.createUrl())!

                try! self.realm.write {
                    let library = RGroup()
                    library.identifier = 1
                    self.realm.add(library)

                    let item = RItem()
                    item.key = key
                    item.rawType = "attachment"
                    item.groupKey = library.identifier
                    item.deleteAllChanges(database: self.realm)
                    item.attachmentNeedsSync = true

                    let contentField = RItemField()
                    contentField.key = FieldKeys.Item.Attachment.contentType
                    contentField.value = "text/plain"
                    item.fields.append(contentField)

                    let filenameField = RItemField()
                    filenameField.key = FieldKeys.Item.Attachment.filename
                    filenameField.value = filename
                    item.fields.append(filenameField)

                    self.realm.add(item)
                }

                createStub(for: AuthorizeUploadRequest(libraryId: libraryId, userId: self.userId, key: key,
                                                       filename: filename, filesize: UInt64(data.count), md5: fileMd5, mtime: 123,
                                                       oldMd5: nil),
                           baseUrl: baseUrl, jsonResponse: ["exists": 1])

                waitUntil(timeout: .seconds(10), action: { doneAction in
                    UploadAttachmentSyncAction(key: key,
                                               file: file,
                                               filename: filename,
                                               md5: fileMd5,
                                               mtime: 123,
                                               libraryId: libraryId,
                                               userId: self.userId,
                                               oldMd5: nil,
                                               apiClient: TestControllers.apiClient,
                                               dbStorage: self.dbStorage,
                                               fileStorage: TestControllers.fileStorage,
                                               webDavController: self.webDavController,
                                               schemaController: TestControllers.schemaController,
                                               dateParser: TestControllers.dateParser,
                                               queue: DispatchQueue.main,
                                               scheduler: MainScheduler.instance,
                                               disposeBag: self.disposeBag).result
                                         .subscribe(onSuccess: { _ in
                                             doneAction()
                                         }, onFailure: { error in
                                             if let error = error as? SyncActionError {
                                                 switch error {
                                                 case .attachmentAlreadyUploaded:
                                                     doneAction()
                                                     return
                                                 default: break
                                                 }
                                             }
                                             fail("Unknown error: \(error.localizedDescription)")
                                             doneAction()
                                         })
                                         .disposed(by: self.disposeBag)
                })
            }

            it("uploads new file") {
                let key = "AAAAAAAA"
                let filename = "doc.txt"
                let libraryId = LibraryIdentifier.group(1)
                let file = Files.attachmentFile(in: libraryId, key: key, filename: filename, contentType: "text/plain")

                let data = "test string".data(using: .utf8)!
                try! FileStorageController().write(data, to: file, options: .atomicWrite)
                let fileMd5 = md5(from: file.createUrl())!

                try! self.realm.write {
                    let library = RGroup()
                    library.identifier = 1
                    self.realm.add(library)

                    let item = RItem()
                    item.key = key
                    item.rawType = "attachment"
                    item.groupKey = library.identifier
                    item.deleteAllChanges(database: self.realm)
                    item.attachmentNeedsSync = true

                    let contentField = RItemField()
                    contentField.key = FieldKeys.Item.Attachment.contentType
                    contentField.value = "text/plain"
                    item.fields.append(contentField)

                    let filenameField = RItemField()
                    filenameField.key = FieldKeys.Item.Attachment.filename
                    filenameField.value = filename
                    item.fields.append(filenameField)

                    self.realm.add(item)
                }

                createStub(for: AuthorizeUploadRequest(libraryId: libraryId, userId: self.userId, key: key, filename: filename, filesize: UInt64(data.count), md5: fileMd5, mtime: 123, oldMd5: nil),
                           baseUrl: baseUrl, jsonResponse: ["url": "https://www.upload-test.org/", "uploadKey": "key", "params": ["key": "key"]])
                createStub(for: RegisterUploadRequest(libraryId: libraryId, userId: self.userId, key: key, uploadKey: "key", oldMd5: nil),
                           baseUrl: baseUrl, headers: nil, statusCode: 204, jsonResponse: [:])
                stub(condition: { request -> Bool in
                    return request.url?.absoluteString == "https://www.upload-test.org/"
                }, response: { _ -> HTTPStubsResponse in
                    return HTTPStubsResponse(jsonObject: [:], statusCode: 201, headers: nil)
                })

                waitUntil(timeout: .seconds(10), action: { doneAction in
                    UploadAttachmentSyncAction(key: key,
                                               file: file,
                                               filename: filename,
                                               md5: fileMd5,
                                               mtime: 123,
                                               libraryId: libraryId,
                                               userId: self.userId,
                                               oldMd5: nil,
                                               apiClient: TestControllers.apiClient,
                                               dbStorage: self.dbStorage,
                                               fileStorage: TestControllers.fileStorage,
                                               webDavController: self.webDavController,
                                               schemaController: TestControllers.schemaController,
                                               dateParser: TestControllers.dateParser,
                                               queue: DispatchQueue.main,
                                               scheduler: MainScheduler.instance,
                                               disposeBag: self.disposeBag).result
                                         .subscribe(onSuccess: { _ in
                                             self.realm.refresh()

                                             let item = self.realm.objects(RItem.self).filter(.key(key)).first
                                             expect(item?.attachmentNeedsSync).to(beFalse())

                                             doneAction()
                                         }, onFailure: { error in
                                             fail("Unknown error: \(error.localizedDescription)")
                                             doneAction()
                                         })
                                         .disposed(by: self.disposeBag)
                })
            }
        }
    }
}

extension SyncActionError: Equatable {
    public static func == (lhs: SyncActionError, rhs: SyncActionError) -> Bool {
        switch (lhs, rhs) {
        case (.attachmentItemNotSubmitted, .attachmentItemNotSubmitted), (.attachmentAlreadyUploaded, .attachmentAlreadyUploaded), (.submitUpdateFailures, .submitUpdateFailures):
            return true
        case (.attachmentMissing(let lKey, let lLibraryId, let lTitle), .attachmentMissing(let rKey, let rLibraryId, let rTitle)):
            return lKey == rKey && lTitle == rTitle && lLibraryId == rLibraryId
        default:
            return false
        }
    }
}

private class WebDavTestController: WebDavController {
    enum Error: Swift.Error {
        case shouldntBeCalled
    }

    let sessionStorage: WebDavSessionStorage
    var authToken: String?

    init() {
        self.sessionStorage = WebDavSession()
    }

    func checkServer(queue: DispatchQueue) -> Single<URL> {
        return Single.error(Error.shouldntBeCalled)
    }

    func download(key: String, file: File, queue: DispatchQueue) -> Observable<DownloadRequest> {
        return Observable.error(Error.shouldntBeCalled)
    }

    func prepareForUpload(key: String, mtime: Int, hash: String, file: File, queue: DispatchQueue) -> Single<WebDavUploadResult> {
        return Single.error(Error.shouldntBeCalled)
    }

    func upload(request: AttachmentUploadRequest, fromFile file: File, queue: DispatchQueue) -> Single<(Data?, HTTPURLResponse)> {
        return Single.error(Error.shouldntBeCalled)
    }

    func finishUpload(key: String, result: Result<(Int, String, URL), Swift.Error>, file: File?, queue: DispatchQueue) -> Single<()> {
        return Single.error(Error.shouldntBeCalled)
    }

    func delete(keys: [String], queue: DispatchQueue) -> Single<WebDavDeletionResult> {
        return Single.error(Error.shouldntBeCalled)
    }

    func resetVerification() {
        self.sessionStorage.isVerified = false
    }

    func createZoteroDirectory(queue: DispatchQueue) -> Single<()> {
        return Single.error(Error.shouldntBeCalled)
    }

    func cancelDeletions() {}
}

private class WebDavSession: WebDavSessionStorage {
    var isEnabled: Bool = false
    var isVerified: Bool = false
    var username: String = ""
    var url: String = ""
    var scheme: WebDavScheme = .http
    var password: String = ""

    func createToken() throws -> String {
        return "\(self.username):\(self.password)".data(using: .utf8).flatMap({ $0.base64EncodedString(options: []) }) ?? ""
    }
}
