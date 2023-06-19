//
//  self.swift
//  ZoteroTests
//
//  Created by Michal Rentka on 08/02/2019.
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

final class SyncControllerSpec: QuickSpec {
    private let userId = 100
    private let userLibraryId: LibraryIdentifier = .custom(.myLibrary)
    // Store realm so that it's not deallocated and its data removed
    private var realmConfig: Realm.Configuration!
    private var realm: Realm!
    private var syncController: SyncController!
    private var webDavController: WebDavController!
    private var attachmentDownloader: AttachmentDownloader!
    private var backgroundUploaderContext: BackgroundUploaderContext!
    private var dbStorage: DbStorage!

    private func createNewSyncController() {
        let config = Realm.Configuration(inMemoryIdentifier: UUID().uuidString)
        let realm = try! Realm(configuration: config)
        try! realm.write {
            let myLibrary = RCustomLibrary()
            myLibrary.type = .myLibrary
            realm.add(myLibrary)

            let versions = RVersions()
            myLibrary.versions = versions
        }
        let webDavSession = WebDavCredentials(isEnabled: false, username: "", password: "", scheme: .http, url: "", isVerified: false)

        self.backgroundUploaderContext = BackgroundUploaderContext()
        self.realmConfig = config
        self.realm = realm
        self.dbStorage = RealmDbStorage(config: config)
        self.webDavController = WebDavControllerImpl(dbStorage: dbStorage, fileStorage: TestControllers.fileStorage, sessionStorage: webDavSession)
        self.attachmentDownloader = AttachmentDownloader(
            userId: self.userId,
            apiClient: TestControllers.apiClient,
            fileStorage: TestControllers.fileStorage,
            dbStorage: self.dbStorage,
            webDavController: self.webDavController
        )
        self.syncController = SyncController(
            userId: self.userId,
            apiClient: TestControllers.apiClient,
            dbStorage: dbStorage,
            fileStorage: TestControllers.fileStorage,
            schemaController: TestControllers.schemaController,
            dateParser: TestControllers.dateParser,
            backgroundUploaderContext: self.backgroundUploaderContext,
            webDavController: self.webDavController,
            attachmentDownloader: self.attachmentDownloader,
            syncDelayIntervals: [0, 1, 2, 3],
            maxRetryCount: 4
        )
        self.syncController.set(coordinator: TestConflictCoordinator(createZoteroDirectory: true))
    }

    override func spec() {
        beforeEach {
            HTTPStubs.removeAllStubs()
            Defaults.shared.userId = self.userId

            self.realm = nil
            self.syncController = nil
        }

        describe("Syncing") {
            let baseUrl = URL(string: ApiConstants.baseUrlString)!

            describe("Download") {
                it("should download items into a new library") {
                    let header = ["last-modified-version": "3"]
                    let libraryId = self.userLibraryId
                    let objects = SyncObject.allCases

                    var versionResponses: [SyncObject: Any] = [:]
                    objects.forEach { object in
                        switch object {
                        case .collection:
                            versionResponses[object] = ["AAAAAAAA": 1]

                        case .search:
                            versionResponses[object] = ["AAAAAAAA": 2]

                        case .item:
                            versionResponses[object] = ["AAAAAAAA": 3]

                        case .trash:
                            versionResponses[object] = ["BBBBBBBB": 3]
                        case .settings: break
                        }
                    }

                    let objectKeys: [SyncObject: String] = [.collection: "AAAAAAAA",
                                                            .search: "AAAAAAAA",
                                                            .item: "AAAAAAAA",
                                                            .trash: "BBBBBBBB"]
                    var objectResponses: [SyncObject: [[String: Any]]] = [:]
                    let libraryJson: [String: Any] = ["id": 0, "type": "user", "name": "A"]
                    for object in objects {
                        switch object {
                        case .collection:
                            objectResponses[object] = [["key": "AAAAAAAA",
                                                        "version": 1,
                                                        "library": libraryJson,
                                                        "data": ["name": "A"]]]

                        case .search:
                            objectResponses[object] = [["key": "AAAAAAAA",
                                                        "version": 2,
                                                        "library": libraryJson,
                                                        "data": ["name": "A",
                                                                 "conditions": [["condition": "itemType",
                                                                                 "operator": "is",
                                                                                 "value": "thesis"]]] as [String: Any]]]

                        case .item:
                            objectResponses[object] = [["key": "AAAAAAAA",
                                                        "version": 3,
                                                        "library": libraryJson,
                                                        "data": ["title": "A", "itemType": "thesis",
                                                                 "tags": [["tag": "A"]]] as [String: Any]]]

                        case .trash:
                            objectResponses[object] = [["key": "BBBBBBBB",
                                                        "version": 4,
                                                        "library": libraryJson,
                                                        "data": ["note": "<p>This is a note</p>",
                                                                 "parentItem": "AAAAAAAA",
                                                                 "itemType": "note",
                                                                 "deleted": 1] as [String: Any]]]

                        case .settings: break
                        }
                    }

                    createStub(for: GroupVersionsRequest(userId: self.userId), baseUrl: baseUrl, headers: header, jsonResponse: [:] as [String: Any])
                    objects.forEach { object in
                        createStub(
                            for: VersionsRequest(libraryId: libraryId, userId: self.userId, objectType: object, version: 0),
                            baseUrl: baseUrl,
                            headers: header,
                            jsonResponse: versionResponses[object] ?? [:] as [String: Any]
                        )
                    }
                    objects.forEach { object in
                        createStub(
                            for: ObjectsRequest(libraryId: libraryId, userId: self.userId, objectType: object, keys: (objectKeys[object] ?? "")),
                            baseUrl: baseUrl,
                            headers: header,
                            jsonResponse: objectResponses[object] ?? [:] as [String: Any]
                        )
                    }
                    createStub(for: KeyRequest(), baseUrl: baseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys", withExtension: "json")!)
                    createStub(
                        for: SettingsRequest(libraryId: libraryId, userId: self.userId, version: 0),
                        baseUrl: baseUrl,
                        headers: header,
                        jsonResponse: ["tagColors": ["value": [["name": "A", "color": "#CC66CC"]], "version": 2] as [String: Any]]
                    )
                    createStub(
                        for: DeletionsRequest(libraryId: libraryId, userId: self.userId, version: 0),
                        baseUrl: baseUrl,
                        headers: header,
                        jsonResponse: ["collections": [] as [Any], "searches": [] as [Any], "items": [] as [Any], "tags": [] as [Any]]
                    )

                    self.createNewSyncController()

                    waitUntil(timeout: .seconds(10)) { doneAction in
                        self.syncController.reportFinish = { _ in
                            let realm = try! Realm(configuration: self.realmConfig)
                            realm.refresh()

                            let library = realm.objects(RCustomLibrary.self).first
                            expect(libraryId).toNot(beNil())
                            expect(library?.type).to(equal(.myLibrary))

                            let collections = realm.objects(RCollection.self).filter(.library(with: .custom(.myLibrary)))
                            let items = realm.objects(RItem.self).filter(.library(with: .custom(.myLibrary)))
                            let tags = realm.objects(RTag.self).filter(.library(with: .custom(.myLibrary)))

                            expect(collections.count).to(equal(1))
                            expect(items.count).to(equal(2))
//                            expect(library?.searches.count).to(equal(1))
                            expect(tags.count).to(equal(1))
                            expect(realm.objects(RCustomLibrary.self).count).to(equal(1))
                            expect(realm.objects(RGroup.self).count).to(equal(0))
                            expect(realm.objects(RCollection.self).count).to(equal(1))
//                            expect(realm.objects(RSearch.self).count).to(equal(1))
                            expect(realm.objects(RItem.self).count).to(equal(2))
                            expect(realm.objects(RTag.self).count).to(equal(1))

                            let versions = library?.versions
                            expect(versions).toNot(beNil())
                            expect(versions?.collections).to(equal(3))
                            expect(versions?.deletions).to(equal(3))
                            expect(versions?.items).to(equal(3))
//                            expect(versions?.searches).to(equal(3))
                            expect(versions?.settings).to(equal(3))
                            expect(versions?.trash).to(equal(3))

                            let collection = realm.objects(RCollection.self).first
                            expect(collection?.key).to(equal("AAAAAAAA"))
                            expect(collection?.name).to(equal("A"))
                            expect(collection?.syncState).to(equal(.synced))
                            expect(collection?.version).to(equal(1))
                            expect(collection?.customLibraryKey).to(equal(RCustomLibraryType.myLibrary))
                            expect(collection?.parentKey).to(beNil())
                            let children = realm.objects(RCollection.self).filter(.parentKey("AAAAAAAA", in: .custom(.myLibrary)))
                            expect(children.count).to(equal(0))

                            let item = realm.objects(RItem.self).filter("key = %@", "AAAAAAAA").first
                            expect(item).toNot(beNil())
                            expect(item?.baseTitle).to(equal("A"))
                            expect(item?.version).to(equal(3))
                            expect(item?.trash).to(beFalse())
                            expect(item?.syncState).to(equal(.synced))
                            expect(item?.customLibraryKey).to(equal(RCustomLibraryType.myLibrary))
                            expect(item?.collections.count).to(equal(0))
                            expect(item?.fields.count).to(equal(1))
                            expect(item?.fields.first?.key).to(equal("title"))
                            expect(item?.parent).to(beNil())
                            expect(item?.children.count).to(equal(1))
                            expect(item?.tags.count).to(equal(1))
                            expect(item?.tags.first?.tag?.name).to(equal("A"))

                            let item2 = realm.objects(RItem.self).filter("key = %@", "BBBBBBBB").first
                            expect(item2).toNot(beNil())
                            expect(item2?.baseTitle).to(equal("This is a note"))
                            expect(item2?.version).to(equal(4))
                            expect(item2?.trash).to(beTrue())
                            expect(item2?.syncState).to(equal(.synced))
                            expect(item2?.customLibraryKey).to(equal(RCustomLibraryType.myLibrary))
                            expect(item2?.collections.count).to(equal(0))
                            expect(item?.fields.count).to(equal(1))
                            expect(item2?.parent?.key).to(equal("AAAAAAAA"))
                            expect(item2?.children.count).to(equal(0))
                            expect(item2?.tags.count).to(equal(0))
                            let noteField = item2?.fields.first
                            expect(noteField?.key).to(equal("note"))
                            expect(noteField?.value).to(equal("<p>This is a note</p>"))

//                            let search = realm.objects(RSearch.self).first
//                            expect(search?.key).to(equal("AAAAAAAA"))
//                            expect(search?.version).to(equal(2))
//                            expect(search?.name).to(equal("A"))
//                            expect(search?.syncState).to(equal(.synced))
//                            expect(search?.customLibrary?.type).to(equal(.myLibrary))
//                            expect(search?.conditions.count).to(equal(1))
//                            let condition = search?.conditions.first
//                            expect(condition?.condition).to(equal("itemType"))
//                            expect(condition?.operator).to(equal("is"))
//                            expect(condition?.value).to(equal("thesis"))

                            let tag = realm.objects(RTag.self).first
                            expect(tag?.name).to(equal("A"))
                            expect(tag?.color).to(equal("#CC66CC"))

                            doneAction()
                        }

                        self.syncController?.start(type: .normal, libraries: .all, retryAttempt: 0)
                    }
                }

                it("should download items into a new read-only group") {
                    let header = ["last-modified-version": "3"]
                    let groupId = 123
                    let libraryId = LibraryIdentifier.group(groupId)
                    let objects = SyncObject.allCases

                    var versionResponses: [SyncObject: Any] = [:]
                    objects.forEach { object in
                        switch object {
                        case .collection:
                            versionResponses[object] = ["AAAAAAAA": 1]

                        case .search:
                            versionResponses[object] = ["AAAAAAAA": 2]

                        case .item:
                            versionResponses[object] = ["AAAAAAAA": 3]

                        case .trash:
                            versionResponses[object] = ["BBBBBBBB": 3]
                        case .settings: break
                        }
                    }

                    let objectKeys: [SyncObject: String] = [.collection: "AAAAAAAA",
                                                            .search: "AAAAAAAA",
                                                            .item: "AAAAAAAA",
                                                            .trash: "BBBBBBBB"]
                    var objectResponses: [SyncObject: Any] = [:]
                    objects.forEach { object in
                        switch object {
                        case .collection:
                            objectResponses[object] = [["key": "AAAAAAAA",
                                                        "version": 1,
                                                        "library": ["id": groupId, "type": "group", "name": "A"] as [String: Any],
                                                        "data": ["name": "A"]] as [String: Any]]

                        case .search:
                            objectResponses[object] = [["key": "AAAAAAAA",
                                                        "version": 2,
                                                        "library": ["id": groupId, "type": "group", "name": "A"] as [String: Any],
                                                        "data": ["name": "A",
                                                                 "conditions": [["condition": "itemType",
                                                                                 "operator": "is",
                                                                                 "value": "thesis"]]] as [String: Any]] as [String: Any]]

                        case .item:
                            objectResponses[object] = [["key": "AAAAAAAA",
                                                        "version": 3,
                                                        "library": ["id": groupId, "type": "group", "name": "A"] as [String: Any],
                                                        "data": ["title": "A", "itemType": "thesis", "tags": [["tag": "A"]]] as [String: Any]] as [String: Any]]

                        case .trash:
                            objectResponses[object] = [["key": "BBBBBBBB",
                                                        "version": 4,
                                                        "library": ["id": groupId, "type": "group", "name": "A"] as [String: Any],
                                                        "data": ["note": "<p>This is a note</p>",
                                                                 "parentItem": "AAAAAAAA",
                                                                 "itemType": "note",
                                                                 "deleted": 1] as [String: Any]] as [String: Any]]

                        case .settings: break
                        }
                    }

                    let groupVersionsResponse: [String: Any] = [groupId.description: 2]
                    let groupObjectResponse: [String: Any] = ["id": groupId,
                                                              "version": 2,
                                                              "data": ["name": "Group",
                                                                       "owner": self.userId,
                                                                       "type": "Private",
                                                                       "description": "",
                                                                       "libraryEditing": "members",
                                                                       "libraryReading": "members",
                                                                       "fileEditing": "members"] as [String: Any]]

                    let myLibrary = self.userLibraryId

                    createStub(for: GroupVersionsRequest(userId: self.userId), baseUrl: baseUrl, headers: header,
                               jsonResponse: groupVersionsResponse)
                    objects.forEach { object in
                        createStub(for: VersionsRequest(libraryId: myLibrary, userId: self.userId, objectType: object, version: 0),
                                   baseUrl: baseUrl, headers: header, jsonResponse: [:] as [String: Any])
                    }
                    createStub(for: GroupRequest(identifier: groupId), baseUrl: baseUrl, headers: header, jsonResponse: groupObjectResponse)
                    for object in objects {
                        createStub(for: VersionsRequest(libraryId: libraryId, userId: self.userId, objectType: object, version: 0),
                                   baseUrl: baseUrl, headers: header, jsonResponse: (versionResponses[object] ?? [:] as [String: Any]))
                    }
                    for object in objects {
                        createStub(for: ObjectsRequest(libraryId: libraryId, userId: self.userId, objectType: object, keys: (objectKeys[object] ?? "")),
                                   baseUrl: baseUrl, headers: header, jsonResponse: (objectResponses[object] ?? [:] as [String: Any]))
                    }
                    createStub(for: KeyRequest(), baseUrl: baseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys", withExtension: "json")!)
                    createStub(
                        for: SettingsRequest(libraryId: myLibrary, userId: self.userId, version: 0),
                        baseUrl: baseUrl,
                        headers: header,
                        jsonResponse: ["tagColors": ["value": [] as [Any], "version": 2] as [String: Any]]
                    )
                    createStub(
                        for: SettingsRequest(libraryId: libraryId, userId: self.userId, version: 0),
                        baseUrl: baseUrl,
                        headers: header,
                        jsonResponse: ["tagColors": ["value": [["name": "A", "color": "#CC66CC"]], "version": 2] as [String: Any]]
                    )
                    createStub(
                        for: DeletionsRequest(libraryId: myLibrary, userId: self.userId, version: 0),
                        baseUrl: baseUrl,
                        headers: header,
                        jsonResponse: ["collections": [] as [Any], "searches": [] as [Any], "items": [] as [Any], "tags": [] as [Any]]
                    )
                    createStub(
                        for: DeletionsRequest(libraryId: libraryId, userId: self.userId, version: 0),
                        baseUrl: baseUrl,
                        headers: header,
                        jsonResponse: ["collections": [] as [Any], "searches": [] as [Any], "items": [] as [Any], "tags": [] as [Any]]
                    )

                    self.createNewSyncController()

                    waitUntil(timeout: .seconds(10)) { doneAction in
                        self.syncController.reportFinish = { _ in
                            let realm = try! Realm(configuration: self.realmConfig)
                            realm.refresh()

                            let myLibrary = realm.object(ofType: RCustomLibrary.self, forPrimaryKey: RCustomLibraryType.myLibrary.rawValue)
                            expect(myLibrary).toNot(beNil())

                            let collections = realm.objects(RCollection.self).filter(.library(with: .custom(.myLibrary)))
                            let items = realm.objects(RItem.self).filter(.library(with: .custom(.myLibrary)))
//                            let searches = realm.objects(RSearch.self).filter(.library(with: .custom(.myLibrary)))
                            let tags = realm.objects(RTag.self).filter(.library(with: .custom(.myLibrary)))

                            expect(collections.count).to(equal(0))
                            expect(items.count).to(equal(0))
//                            expect(searches.count).to(equal(0))
                            expect(tags.count).to(equal(0))

                            let group = realm.object(ofType: RGroup.self, forPrimaryKey: groupId)
                            expect(group).toNot(beNil())

                            let gCollections = realm.objects(RCollection.self).filter(.library(with: .group(groupId)))
                            let gItems = realm.objects(RItem.self).filter(.library(with: .group(groupId)))
//                            let gSearches = realm.objects(RSearch.self).filter(.library(with: .group(groupId)))
                            let gTags = realm.objects(RTag.self).filter(.library(with: .group(groupId)))

                            expect(gCollections.count).to(equal(1))
                            expect(gItems.count).to(equal(2))
//                            expect(gSearches.count).to(equal(1))
                            expect(gTags.count).to(equal(1))

                            let versions = group?.versions
                            expect(versions).toNot(beNil())
                            expect(versions?.collections).to(equal(3))
                            expect(versions?.deletions).to(equal(3))
                            expect(versions?.items).to(equal(3))
//                            expect(versions?.searches).to(equal(3))
                            expect(versions?.settings).to(equal(3))
                            expect(versions?.trash).to(equal(3))

                            let collection = realm.objects(RCollection.self).filter(.key("AAAAAAAA", in: .group(groupId))).first
                            expect(collection).toNot(beNil())
                            let item = realm.objects(RItem.self).filter(.key("AAAAAAAA", in: .group(groupId))).first
                            expect(item).toNot(beNil())
                            let item2 = realm.objects(RItem.self).filter(.key("BBBBBBBB", in: .group(groupId))).first
                            expect(item2).toNot(beNil())
//                            let search = realm.objects(RSearch.self)
//                                .filter(.key("AAAAAAAA", in: .group(groupId))).first
//                            expect(search).toNot(beNil())
                            let tag = realm.objects(RTag.self).filter(.name("A", in: .group(groupId))).first
                            expect(tag).toNot(beNil())

                            doneAction()
                        }

                        self.syncController.start(type: .normal, libraries: .all, retryAttempt: 0)
                    }
                }

                it("should apply remote deletions") {
                    let header = ["last-modified-version": "3"]
                    let libraryId = self.userLibraryId
                    let itemToDelete = "CCCCCCCC"
                    let objects = SyncObject.allCases

                    self.createNewSyncController()

                    try! self.realm.write {
                        let item = RItem()
                        item.key = itemToDelete
                        item.baseTitle = "Delete me"
                        item.libraryId = .custom(.myLibrary)
                        self.realm.add(item)
                    }

                    let toBeDeletedItem = self.realm.objects(RItem.self).filter(.key(itemToDelete, in: .custom(.myLibrary))).first
                    expect(toBeDeletedItem).toNot(beNil())

                    createStub(for: GroupVersionsRequest(userId: self.userId), baseUrl: baseUrl, headers: header, jsonResponse: [:] as [String: Any])
                    objects.forEach { object in
                        createStub(
                            for: VersionsRequest(libraryId: libraryId, userId: self.userId, objectType: object, version: 0),
                            baseUrl: baseUrl,
                            headers: header,
                            jsonResponse: [:] as [String: Any]
                        )
                    }
                    createStub(for: KeyRequest(), baseUrl: baseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys", withExtension: "json")!)
                    createStub(
                        for: SettingsRequest(libraryId: libraryId, userId: self.userId, version: 0),
                        baseUrl: baseUrl,
                        headers: header,
                        jsonResponse: ["tagColors": ["value": [] as [Any], "version": 2] as [String: Any]]
                    )
                    createStub(
                        for: DeletionsRequest(libraryId: libraryId, userId: self.userId, version: 0),
                        baseUrl: baseUrl,
                        headers: header,
                        jsonResponse: ["collections": [] as [Any], "searches": [] as [Any], "items": [itemToDelete], "tags": [] as [Any]]
                    )

                    waitUntil(timeout: .seconds(10)) { doneAction in
                        self.syncController.reportFinish = { _ in
                            let realm = try! Realm(configuration: self.realmConfig)
                            realm.refresh()

                            let deletedItem = realm.objects(RItem.self).filter(.key(itemToDelete, in: .custom(.myLibrary))).first
                            expect(deletedItem).to(beNil())

                            doneAction()
                        }

                        self.syncController.start(type: .normal, libraries: .all, retryAttempt: 0)
                    }
                }

                // TODO: Enable when proper CR is implemented
//                it("should ignore remote deletions if local object changed") {
//                    let header = ["last-modified-version" : "3"]
//                    let libraryId = self.userLibraryId
//                    let itemToDelete = "DDDDDDDD"
//                    let objects = SyncObject.allCases
//
//                    let realm = self.realm
//                    try! realm.write {
//                        let myLibrary = self.realm.objects(RCustomLibrary.self).first
//                        let item = RItem()
//                        item.key = itemToDelete
//                        item.title = "Delete me"
//                        item.changedFields = .fields
//                        item.customLibrary = myLibrary
//                        realm.add(item)
//                    }
//
//                    let predicate = Predicates.key(itemToDelete, in: .custom(.myLibrary))
//                    let toBeDeletedItem = realm.objects(RItem.self).filter(predicate).first
//                    expect(toBeDeletedItem).toNot(beNil())
//
//                    var statusCode: Int32 = 412
//                    let request = UpdatesRequest(libraryId: libraryId, userId: self.userId, objectType: .item, params: [], version: 0)
//                    // We don't care about specific post params here, we just want to track all update requests
//                    let condition = request.stubCondition(with: baseUrl, ignorePostParams: true)
//                    stub(condition: condition, response: { _ -> HTTPStubsResponse in
//                        let code = statusCode
//                        statusCode = 200
//                        return HTTPStubsResponse(jsonObject: [:], statusCode: code, headers: header)
//                    })
//                    objects.forEach { object in
//                        let version: Int? = object == .group ? nil : 0
//                        createStub(for: VersionsRequest(libraryId: libraryId, userId: self.userId,
//                                                                     objectType: object, version: version),
//                                        baseUrl: baseUrl, headers: header,
//                                        response: [:])
//                    }
//                    createStub(for: KeyRequest(), baseUrl: baseUrl, response: ["access": ["":""]])
//                    createStub(for: SettingsRequest(libraryId: libraryId, userId: self.userId, version: 0),
//                                    baseUrl: baseUrl, headers: header,
//                                    response: ["tagColors" : ["value": [], "version": 2]])
//                    createStub(for: DeletionsRequest(libraryId: libraryId, userId: self.userId, version: 0),
//                                    baseUrl: baseUrl, headers: header,
//                                    response: ["collections": [], "searches": [], "items": [itemToDelete], "tags": []])
//
//                    self.controller = SyncController(userId: self.userId,
//                                                     handler: self.syncHandler,
//                                                     conflictDelays: self.delays)
//
//                    waitUntil(timeout: 10) { doneAction in
//                        self.controller?.reportFinish = { result in
//                            let realm = try! Realm(configuration: self.realmConfig)
//                            realm.refresh()
//
//                            switch result {
//                            case .success(let data):
//                                expect(data.0).to(contain(.resolveConflict(itemToDelete, library)))
//                            case .failure:
//                                fail("Sync aborted")
//                            }
//
//                            let predicate = Predicates.key(itemToDelete, in: .custom(.myLibrary))
//                            let deletedItem = realm.objects(RItem.self).filter(predicate).first
//                            expect(deletedItem).toNot(beNil())
//
//                            doneAction()
//                        }
//
//                        self.controller?.start(type: .normal, libraries: .all)
//                    }
//                }

                it("should handle new remote item referencing locally missing collection") {
                    let header = ["last-modified-version": "3"]
                    let libraryId = self.userLibraryId
                    let objects = SyncObject.allCases
                    let itemKey = "AAAAAAAA"
                    let collectionKey = "CCCCCCCC"
                    let itemResponse = [["key": itemKey,
                                         "version": 3,
                                         "library": ["id": 0, "type": "user", "name": "A"] as [String: Any],
                                         "data": ["title": "A", "itemType": "thesis", "collections": [collectionKey]] as [String: Any]] as [String: Any]]

                    self.createNewSyncController()

                    let realm = self.realm!
                    let collection = realm.objects(RItem.self).filter("key = %@", collectionKey).first
                    expect(collection).to(beNil())

                    createStub(for: GroupVersionsRequest(userId: self.userId), baseUrl: baseUrl, headers: header, jsonResponse: [:] as [String: Any])
                    objects.forEach { object in
                        if object == .item {
                            createStub(
                                for: VersionsRequest(libraryId: libraryId, userId: self.userId, objectType: object, version: 0),
                                baseUrl: baseUrl,
                                headers: header,
                                jsonResponse: [itemKey: 3]
                            )
                        } else {
                            createStub(
                                for: VersionsRequest(libraryId: libraryId, userId: self.userId, objectType: object, version: 0),
                                baseUrl: baseUrl,
                                headers: header,
                                jsonResponse: [:] as [String: Any]
                            )
                        }
                    }
                    createStub(for: KeyRequest(), baseUrl: baseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys", withExtension: "json")!)
                    createStub(
                        for: ObjectsRequest(libraryId: libraryId, userId: self.userId, objectType: .item, keys: itemKey),
                        baseUrl: baseUrl,
                        headers: header,
                        jsonResponse: itemResponse
                    )
                    createStub(
                        for: SettingsRequest(libraryId: libraryId, userId: self.userId, version: 0),
                        baseUrl: baseUrl,
                        headers: header,
                        jsonResponse: ["tagColors": ["value": [] as [Any], "version": 2] as [String: Any]]
                    )
                    createStub(
                        for: DeletionsRequest(libraryId: libraryId, userId: self.userId, version: 0),
                        baseUrl: baseUrl,
                        headers: header,
                        jsonResponse: ["collections": [] as [Any], "searches": [] as [Any], "items": [] as [Any], "tags": [] as [Any]]
                    )

                    waitUntil(timeout: .seconds(10)) { doneAction in
                        self.syncController.reportFinish = { _ in
                            let realm = try! Realm(configuration: self.realmConfig)
                            realm.refresh()

                            let item = realm.objects(RItem.self).filter(.key(itemKey, in: .custom(.myLibrary))).first
                            expect(item).toNot(beNil())
                            expect(item?.syncState).to(equal(.synced))
                            expect(item?.collections.count).to(equal(1))

                            let collection = item?.collections.first
                            expect(collection).toNot(beNil())
                            expect(collection?.key).to(equal(collectionKey))
                            expect(collection?.syncState).to(equal(.dirty))

                            doneAction()
                        }

                        self.syncController.start(type: .normal, libraries: .all, retryAttempt: 0)
                    }
                }

                it("should include unsynced objects in sync queue") {
                    let header = ["last-modified-version": "3"]
                    let libraryId = self.userLibraryId
                    let objects = SyncObject.allCases
                    let unsyncedItemKey = "AAAAAAAA"
                    let responseItemKey = "BBBBBBBB"
                    let itemResponse = [["key": responseItemKey,
                                         "version": 3,
                                         "library": ["id": 0, "type": "user", "name": "A"] as [String: Any],
                                         "data": ["title": "A", "itemType": "thesis"]] as [String: Any],
                                        ["key": unsyncedItemKey,
                                         "version": 3,
                                         "library": ["id": 0, "type": "user", "name": "A"] as [String: Any],
                                         "data": ["title": "B", "itemType": "thesis"]]]

                    self.createNewSyncController()

                    let realm = self.realm!
                    try! realm.write {
                        let item = RItem()
                        item.key = unsyncedItemKey
                        item.syncState = .dirty
                        item.libraryId = .custom(.myLibrary)
                        realm.add(item)
                    }

                    let unsynced = realm.objects(RItem.self).filter(.key(unsyncedItemKey, in: .custom(.myLibrary))).first
                    expect(unsynced).toNot(beNil())
                    expect(unsynced?.syncState).to(equal(.dirty))

                    createStub(for: GroupVersionsRequest(userId: self.userId), baseUrl: baseUrl, headers: header, jsonResponse: [:] as [String: Any])
                    objects.forEach { object in
                        if object == .item {
                            createStub(
                                for: VersionsRequest(libraryId: libraryId, userId: self.userId, objectType: object, version: 0),
                                baseUrl: baseUrl,
                                headers: header,
                                jsonResponse: [responseItemKey: 3]
                            )
                        } else {
                            createStub(
                                for: VersionsRequest(libraryId: libraryId, userId: self.userId, objectType: object, version: 0),
                                baseUrl: baseUrl,
                                headers: header,
                                jsonResponse: [:] as [String: Any]
                            )
                        }
                    }
                    createStub(for: KeyRequest(), baseUrl: baseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys", withExtension: "json")!)
                    createStub(
                        for: ObjectsRequest(libraryId: libraryId, userId: self.userId, objectType: .item, keys: "\(unsyncedItemKey),\(responseItemKey)"),
                        baseUrl: baseUrl,
                        headers: header,
                        jsonResponse: itemResponse
                    )
                    createStub(
                        for: ObjectsRequest(libraryId: libraryId, userId: self.userId, objectType: .item, keys: "\(responseItemKey),\(unsyncedItemKey)"),
                        baseUrl: baseUrl,
                        headers: header,
                        jsonResponse: itemResponse
                    )
                    createStub(
                        for: SettingsRequest(libraryId: libraryId, userId: self.userId, version: 0),
                        baseUrl: baseUrl,
                        headers: header,
                        jsonResponse: ["tagColors": ["value": [] as [Any], "version": 2] as [String: Any]]
                    )
                    createStub(
                        for: DeletionsRequest(libraryId: libraryId, userId: self.userId, version: 0),
                        baseUrl: baseUrl,
                        headers: header,
                        jsonResponse: ["collections": [] as [Any], "searches": [] as [Any], "items": [] as [Any], "tags": [] as [Any]]
                    )

                    waitUntil(timeout: .seconds(10)) { doneAction in
                        self.syncController.reportFinish = { result in
                            let realm = try! Realm(configuration: self.realmConfig)
                            realm.refresh()

                            switch result {
                            case .success(let data):
                                let actions: [SyncController.Action] = data.0
                                let itemAction = actions.filter({ action -> Bool in
                                    switch action {
                                    case .syncBatchesToDb(let batches):
                                        guard batches.first?.object == .item,
                                            let strKeys = batches.first?.keys else { return false }
                                        return strKeys.contains(unsyncedItemKey) && strKeys.contains(responseItemKey)

                                    default:
                                        return false
                                    }
                                }).first
                                expect(itemAction).toNot(beNil())

                            case .failure:
                                fail("Sync aborted")
                            }

                            let newItem = realm.objects(RItem.self).filter(.key(responseItemKey, in: .custom(.myLibrary))).first
                            expect(newItem).toNot(beNil())
                            expect(newItem?.baseTitle).to(equal("A"))

                            let oldItem = realm.objects(RItem.self).filter(.key(unsyncedItemKey, in: .custom(.myLibrary))).first
                            expect(oldItem).toNot(beNil())
                            expect(oldItem?.baseTitle).to(equal("B"))
                            expect(oldItem?.syncState).to(equal(.synced))

                            doneAction()
                        }

                        self.syncController.start(type: .normal, libraries: .all, retryAttempt: 0)
                    }
                }

                it("should mark object as needsSync if not parsed correctly and syncRetries should be increased") {
                    let header = ["last-modified-version": "3"]
                    let libraryId = self.userLibraryId
                    let objects = SyncObject.allCases
                    let correctKey = "AAAAAAAA"
                    let incorrectKey = "BBBBBBBB"
                    let itemResponse = [["key": correctKey,
                                         "version": 3,
                                         "library": ["id": 0, "type": "user", "name": "A"] as [String: Any],
                                         "data": ["title": "A", "itemType": "thesis"]] as [String: Any],
                                        ["key": incorrectKey,
                                         "version": 3,
                                         "data": ["title": "A", "itemType": "thesis"]]]

                    createStub(for: GroupVersionsRequest(userId: self.userId), baseUrl: baseUrl, headers: header, jsonResponse: [:] as [String: Any])
                    objects.forEach { object in
                        if object == .item {
                            createStub(
                                for: VersionsRequest(libraryId: libraryId, userId: self.userId, objectType: object, version: 0),
                                baseUrl: baseUrl,
                                headers: header,
                                jsonResponse: [correctKey: 3, incorrectKey: 3]
                            )
                        } else {
                            createStub(
                                for: VersionsRequest(libraryId: libraryId, userId: self.userId, objectType: object, version: 0),
                                baseUrl: baseUrl,
                                headers: header,
                                jsonResponse: [:] as [String: Any]
                            )
                        }
                    }
                    createStub(for: KeyRequest(), baseUrl: baseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys", withExtension: "json")!)
                    createStub(
                        for: ObjectsRequest(libraryId: libraryId, userId: self.userId, objectType: .item, keys: "\(correctKey),\(incorrectKey)"),
                        baseUrl: baseUrl,
                        headers: header,
                        jsonResponse: itemResponse
                    )
                    createStub(
                        for: ObjectsRequest(libraryId: libraryId, userId: self.userId, objectType: .item, keys: "\(incorrectKey),\(correctKey)"),
                        baseUrl: baseUrl,
                        headers: header,
                        jsonResponse: itemResponse
                    )
                    createStub(
                        for: SettingsRequest(libraryId: libraryId, userId: self.userId, version: 0),
                        baseUrl: baseUrl,
                        headers: header,
                        jsonResponse: ["tagColors": ["value": [] as [Any], "version": 2] as [String: Any]]
                    )
                    createStub(
                        for: DeletionsRequest(libraryId: libraryId, userId: self.userId, version: 0),
                        baseUrl: baseUrl,
                        headers: header,
                        jsonResponse: ["collections": [] as [Any], "searches": [] as [Any], "items": [] as [Any], "tags": [] as [Any]]
                    )

                    self.createNewSyncController()

                    waitUntil(timeout: .seconds(10)) { doneAction in
                        self.syncController.reportFinish = { _ in
                            let realm = try! Realm(configuration: self.realmConfig)
                            realm.refresh()

                            let correctItem = realm.objects(RItem.self).filter(.key(correctKey, in: .custom(.myLibrary))).first
                            expect(correctItem).toNot(beNil())
                            expect(correctItem?.syncState).to(equal(.synced))
                            expect(correctItem?.syncRetries).to(equal(0))

                            let incorrectItem = realm.objects(RItem.self).filter(.key(incorrectKey, in: .custom(.myLibrary))).first
                            expect(incorrectItem).toNot(beNil())
                            expect(incorrectItem?.syncState).to(equal(.dirty))
                            expect(incorrectItem?.syncRetries).to(equal(1))

                            doneAction()
                        }

                        self.syncController.start(type: .normal, libraries: .all, retryAttempt: 0)
                    }
                }

                it("should ignore errors when saving downloaded objects") {
                    let header = ["last-modified-version": "2"]
                    let libraryId = self.userLibraryId
                    let objects = SyncObject.allCases

                    var versionResponses: [SyncObject: Any] = [:]
                    objects.forEach { object in
                        switch object {
                        case .collection:
                            versionResponses[object] = ["AAAAAAAA": 1,
                                                        "BBBBBBBB": 1,
                                                        "CCCCCCCC": 1]

                        case .search:
                            versionResponses[object] = ["GGGGGGGG": 1,
                                                        "HHHHHHHH": 1,
                                                        "IIIIIIII": 1]

                        case .item:
                            versionResponses[object] = ["DDDDDDDD": 1,
                                                        "EEEEEEEE": 1,
                                                        "FFFFFFFF": 1]
                        case .trash, .settings: break
                        }
                    }

                    let objectKeys: [SyncObject: String] = [.collection: "AAAAAAAA,BBBBBBBB,CCCCCCCC",
                                                            .search: "GGGGGGGG,HHHHHHHH,IIIIIIII",
                                                            .item: "DDDDDDDD,EEEEEEEE,FFFFFFFF"]
                    var objectResponses: [SyncObject: Any] = [:]
                    objects.forEach { object in
                        switch object {
                        case .collection:
                            objectResponses[object] = [["key": "AAAAAAAA",
                                                        "version": 1,
                                                        "library": ["id": 0, "type": "user", "name": "A"] as [String: Any],
                                                        "data": ["name": "A"]] as [String: Any],
                                                       // Missing parent - should be synced, parent queued
                                                       ["key": "BBBBBBBB",
                                                        "version": 1,
                                                        "library": ["id": 0, "type": "user", "name": "A"] as [String: Any],
                                                        "data": ["name": "B",
                                                                 "parentCollection": "ZZZZZZZZ"]],
                                                       // Unknown field - should be rejected
                                                       ["key": "CCCCCCCC",
                                                        "version": 1,
                                                        "library": ["id": 0, "type": "user", "name": "A"] as [String: Any],
                                                        "data": ["name": "C", "unknownField": 5] as [String: Any]]]

                        case .search:
                                                       // Unknown condition - should be queued
                            objectResponses[object] = [["key": "GGGGGGGG",
                                                        "version": 2,
                                                        "library": ["id": 0, "type": "user", "name": "A"] as [String: Any],
                                                        "data": ["name": "G",
                                                                 "conditions": [["condition": "unknownCondition",
                                                                                 "operator": "is",
                                                                                 "value": "thesis"]]] as [String: Any]] as [String: Any],
                                                       // Unknown operator - should be queued
                                                       ["key": "HHHHHHHH",
                                                        "version": 2,
                                                        "library": ["id": 0, "type": "user", "name": "A"] as [String: Any],
                                                        "data": ["name": "H",
                                                                 "conditions": [["condition": "itemType",
                                                                                 "operator": "unknownOperator",
                                                                                 "value": "thesis"]]] as [String: Any]]]

                        case .item:
                                                       // Unknown field - should be rejected
                            objectResponses[object] = [["key": "DDDDDDDD",
                                                        "version": 3,
                                                        "library": ["id": 0, "type": "user", "name": "A"] as [String: Any],
                                                        "data": ["title": "D", "itemType": "thesis", "tags": [] as [Any], "unknownField": "B"] as [String: Any]],
                                                       // Unknown item type - should be queued
                                                       ["key": "EEEEEEEE",
                                                        "version": 3,
                                                        "library": ["id": 0, "type": "user", "name": "A"] as [String: Any],
                                                        "data": ["title": "E", "itemType": "unknownType", "tags": [] as [Any]] as [String: Any]] as [String: Any],
                                                       // Parent didn't sync, but item is fine - should be synced
                                                       ["key": "FFFFFFFF",
                                                        "version": 3,
                                                        "library": ["id": 0, "type": "user", "name": "A"] as [String: Any],
                                                        "data": ["note": "This is a note", "itemType": "note",
                                                                 "tags": [] as [Any], "parentItem": "EEEEEEEE"] as [String: Any]]]
                        case .trash, .settings: break
                        }
                    }

                    createStub(for: GroupVersionsRequest(userId: self.userId), baseUrl: baseUrl, headers: header, jsonResponse: [:] as [String: Any])
                    objects.forEach { object in
                        createStub(
                            for: VersionsRequest(libraryId: libraryId, userId: self.userId, objectType: object, version: 0),
                            baseUrl: baseUrl,
                            headers: header,
                            jsonResponse: versionResponses[object] ?? [:] as [String: Any]
                        )
                    }
                    objects.forEach { object in
                        createStub(
                            for: ObjectsRequest(libraryId: libraryId, userId: self.userId, objectType: object, keys: (objectKeys[object] ?? "")),
                            baseUrl: baseUrl,
                            headers: header,
                            jsonResponse: objectResponses[object] ?? [:] as [String: Any]
                        )
                    }
                    createStub(for: KeyRequest(), baseUrl: baseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys", withExtension: "json")!)
                    createStub(
                        for: SettingsRequest(libraryId: libraryId, userId: self.userId, version: 0),
                        baseUrl: baseUrl,
                        headers: header,
                        jsonResponse: ["tagColors": ["value": [["name": "A", "color": "#CC66CC"]], "version": 2] as [String: Any]]
                    )
                    createStub(
                        for: DeletionsRequest(libraryId: libraryId, userId: self.userId, version: 0),
                        baseUrl: baseUrl,
                        headers: header,
                        jsonResponse: ["collections": [] as [Any], "searches": [] as [Any], "items": [] as [Any], "tags": [] as [Any]]
                    )

                    self.createNewSyncController()

                    waitUntil(timeout: .seconds(10)) { doneAction in
                        self.syncController.reportFinish = { _ in
                            let realm = try! Realm(configuration: self.realmConfig)
                            realm.refresh()

                            let library = realm.objects(RCustomLibrary.self).first
                            expect(libraryId).toNot(beNil())
                            expect(library?.type).to(equal(.myLibrary))

                            let collections = realm.objects(RCollection.self).filter(.library(with: .custom(.myLibrary)))
                            let items = realm.objects(RItem.self).filter(.library(with: .custom(.myLibrary)))
//                            let searches = realm.objects(RSearch.self).filter(.library(with: .custom(.myLibrary)))

                            expect(collections.count).to(equal(4))
                            expect(items.count).to(equal(3))
//                            expect(searches.count).to(equal(3))
                            expect(realm.objects(RCollection.self).count).to(equal(4))
//                            expect(realm.objects(RSearch.self).count).to(equal(3))
                            expect(realm.objects(RItem.self).count).to(equal(3))

                            let collection = realm.objects(RCollection.self).filter("key = %@", "AAAAAAAA").first
                            expect(collection).toNot(beNil())
                            expect(collection?.name).to(equal("A"))
                            expect(collection?.syncState).to(equal(.synced))
                            expect(collection?.version).to(equal(1))
                            expect(collection?.customLibraryKey).to(equal(RCustomLibraryType.myLibrary))
                            expect(collection?.parentKey).to(beNil())
                            let children = realm.objects(RCollection.self).filter(.parentKey("AAAAAAAA", in: .custom(.myLibrary)))
                            expect(children.count).to(equal(0))

                            let collection2 = realm.objects(RCollection.self).filter("key = %@", "BBBBBBBB").first
                            expect(collection2).toNot(beNil())
                            expect(collection2?.name).to(equal("B"))
                            expect(collection2?.syncState).to(equal(.synced))
                            expect(collection2?.version).to(equal(1))
                            expect(collection2?.customLibraryKey).to(equal(RCustomLibraryType.myLibrary))
                            expect(collection2?.parentKey).to(equal("ZZZZZZZZ"))
                            let children2 = realm.objects(RCollection.self).filter(.parentKey("BBBBBBBB", in: .custom(.myLibrary)))
                            expect(children2.count).to(equal(0))

                            let collection3 = realm.objects(RCollection.self).filter("key = %@", "CCCCCCCC").first
                            expect(collection3?.syncState).to(equal(.dirty))

                            let collection4 = realm.objects(RCollection.self).filter("key = %@", "ZZZZZZZZ").first
                            expect(collection4).toNot(beNil())
                            expect(collection4?.syncState).to(equal(.dirty))
                            expect(collection4?.customLibraryKey).to(equal(RCustomLibraryType.myLibrary))
                            expect(collection4?.parentKey).to(beNil())
                            let children4 = realm.objects(RCollection.self).filter(.parentKey("ZZZZZZZZ", in: .custom(.myLibrary)))
                            expect(children4.count).to(equal(1))

                            let item = realm.objects(RItem.self).filter("key = %@", "DDDDDDDD").first
                            expect(item?.syncState).to(equal(.dirty))

                            let item2 = realm.objects(RItem.self).filter("key = %@", "EEEEEEEE").first
                            expect(item2).toNot(beNil())
                            expect(item2?.syncState).to(equal(.dirty))
                            expect(item2?.parent).to(beNil())
                            expect(item2?.children.count).to(equal(1))

                            let item3 = realm.objects(RItem.self).filter("key = %@", "FFFFFFFF").first
                            expect(item3).toNot(beNil())
                            expect(item3?.syncState).to(equal(.synced))
                            expect(item3?.parent?.key).to(equal("EEEEEEEE"))
                            expect(item3?.parent?.syncState).to(equal(.dirty))
                            expect(item3?.children.count).to(equal(0))

//                            let search = realm.objects(RSearch.self).first
//                            expect(search?.key).to(equal("GGGGGGGG"))
//                            expect(search?.name).to(equal("G"))
//                            expect(search?.syncState).to(equal(.dirty))
//                            expect(search?.conditions.count).to(equal(0))
//
//                            let search2 = realm.objects(RSearch.self).first
//                            expect(search2?.key).to(equal("HHHHHHHH"))
//                            expect(search2?.name).to(equal("H"))
//                            expect(search2?.syncState).to(equal(.dirty))
//                            expect(search2?.conditions.count).to(equal(0))

                            doneAction()
                        }

                        self.syncController.start(type: .normal, libraries: .all, retryAttempt: 0)
                    }
                }

                it("should add items that exist remotely in a locally deleted, remotely modified collection back to collection") {
                    let header = ["last-modified-version": "1"]
                    let libraryId = self.userLibraryId
                    let objects = SyncObject.allCases
                    let collectionKey = "AAAAAAAA"

                    self.createNewSyncController()

                    let realm = self.realm!
                    try! realm.write {
                        let library = realm.object(ofType: RCustomLibrary.self, forPrimaryKey: RCustomLibraryType.myLibrary.rawValue)

                        let versions = RVersions()
                        library?.versions = versions

                        let collection = RCollection()
                        collection.key = collectionKey
                        collection.name = "Locally deleted collection"
                        collection.version = 0
                        collection.trash = true
                        collection.deleted = true
                        collection.libraryId = .custom(.myLibrary)
                        realm.add(collection)

                        let item1 = RItem()
                        item1.key = "BBBBBBBB"
                        item1.baseTitle = "B"
                        item1.libraryId = .custom(.myLibrary)
                        realm.add(item1)
                        collection.items.append(item1)

                        let item2 = RItem()
                        item2.key = "CCCCCCCC"
                        item2.baseTitle = "C"
                        item2.libraryId = .custom(.myLibrary)
                        item2.deleted = true
                        item2.trash = true
                        realm.add(item2)
                        collection.items.append(item2)
                    }

                    var item1Response = self.itemJson(key: "BBBBBBBB", version: 2, type: "book")
                    var item1Data = item1Response["data"] as? [String: Any]
                    item1Data?["collections"] = [collectionKey]
                    item1Response["data"] = item1Data
                    var item2Response = self.itemJson(key: "CCCCCCCC", version: 2, type: "book")
                    var item2Data = item2Response["data"] as? [String: Any]
                    item2Data?["collections"] = [collectionKey]
                    item2Response["data"] = item2Data

                    let versionResponses: [SyncObject: Any] = [.collection: [collectionKey: 1]]
                    let objectKeys: [SyncObject: String] = [.collection: collectionKey]
                    let libraryJson: [String: Any] = ["id": 0, "type": "user", "name": "A"]
                    let collectionData: [[String: Any]] = [["key": collectionKey, "version": 1, "library": libraryJson, "data": ["name": "A"]]]
                    let itemsData = [item1Response, item2Response]
                    let objectResponses: [SyncObject: Any] = [.collection: collectionData, .item: itemsData]

                    createStub(
                        for: SubmitDeletionsRequest(libraryId: libraryId, userId: self.userId, objectType: .collection, keys: [collectionKey], version: 0),
                        baseUrl: baseUrl,
                        headers: header,
                        statusCode: 412,
                        jsonResponse: [:] as [String: Any]
                    )
                    createStub(for: GroupVersionsRequest(userId: self.userId), baseUrl: baseUrl, headers: header, jsonResponse: [:] as [String: Any])
                    objects.forEach { object in
                        createStub(
                            for: VersionsRequest(libraryId: libraryId, userId: self.userId, objectType: object, version: 0),
                            baseUrl: baseUrl,
                            headers: header,
                            jsonResponse: versionResponses[object] ?? [:] as [String: Any]
                        )
                    }
                    objects.forEach { object in
                        createStub(
                            for: ObjectsRequest(libraryId: libraryId, userId: self.userId, objectType: object, keys: (objectKeys[object] ?? "")),
                            baseUrl: baseUrl,
                            headers: header,
                            jsonResponse: objectResponses[object] ?? [:] as [String: Any]
                        )
                    }
                    createStub(for: KeyRequest(), baseUrl: baseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys", withExtension: "json")!)
                    createStub(
                        for: SettingsRequest(libraryId: libraryId, userId: self.userId, version: 0),
                        baseUrl: baseUrl,
                        headers: header,
                        jsonResponse: ["tagColors": ["value": [["name": "A", "color": "#CC66CC"]], "version": 1] as [String: Any]]
                    )
                    createStub(
                        for: DeletionsRequest(libraryId: libraryId, userId: self.userId, version: 0),
                        baseUrl: baseUrl,
                        headers: header,
                        jsonResponse: ["collections": [] as [Any], "searches": [] as [Any], "items": [] as [Any], "tags": [] as [Any]]
                    )

                    waitUntil(timeout: .seconds(10)) { doneAction in
                        self.syncController.reportFinish = { result in
                            switch result {
                            case .failure(let error):
                                fail("Failure: \(error)")

                            case .success(let data):
                                // precondition error should be reported first time, retry
                                guard let error = data.1.first as? Zotero.SyncError.NonFatal, case .preconditionFailed(let libraryId) = error else {
                                    fail("Failure: \(result)")
                                    return
                                }

                                self.syncController.reportFinish = { _ in
                                    let realm = try! Realm(configuration: self.realmConfig)
                                    realm.refresh()

                                    let library = realm.objects(RCustomLibrary.self).first
                                    expect(libraryId).toNot(beNil())
                                    expect(library?.type).to(equal(.myLibrary))

                                    let collections = realm.objects(RCollection.self).filter(.library(with: .custom(.myLibrary)))
                                    let items = realm.objects(RItem.self).filter(.library(with: .custom(.myLibrary)))

                                    expect(collections.count).to(equal(1))
                                    expect(items.count).to(equal(2))
                                    expect(realm.objects(RCollection.self).count).to(equal(1))
                                    expect(realm.objects(RItem.self).count).to(equal(2))

                                    let item = realm.objects(RItem.self).filter("key = %@", "CCCCCCCC").first
                                    expect(item).toNot(beNil())
                                    expect(item?.deleted).to(beFalse())
                                    expect(item?.trash).to(beFalse())

                                    let collection = realm.objects(RCollection.self).filter("key = %@", collectionKey).first
                                    expect(collection).toNot(beNil())
                                    expect(collection?.syncState).to(equal(.synced))
                                    expect(collection?.version).to(equal(1))
                                    expect(collection?.deleted).to(beFalse())
                                    expect(collection?.trash).to(beFalse())
                                    expect(collection?.customLibraryKey).to(equal(RCustomLibraryType.myLibrary))
                                    expect(collection?.parentKey).to(beNil())
                                    expect(collection?.items.count).to(equal(2))

                                    doneAction()
                                }

                                self.syncController.start(type: .prioritizeDownloads, libraries: .specific([libraryId]), retryAttempt: 4)
                            }
                        }

                        self.syncController.start(type: .normal, libraries: .all, retryAttempt: 0)
                    }
                }

                it("should add locally deleted items that exist remotely in a locally deleted, remotely modified collection to sync queue and remove from delete log") {
                    let header = ["last-modified-version": "1"]
                    let libraryId = self.userLibraryId
                    let objects = SyncObject.allCases
                    let collectionKey = "AAAAAAAA"
                    let deletedItemKey = "CCCCCCCC"

                    self.createNewSyncController()

                    let realm = self.realm!
                    try! realm.write {
                        let library = realm.object(ofType: RCustomLibrary.self, forPrimaryKey: RCustomLibraryType.myLibrary.rawValue)

                        let versions = RVersions()
                        versions.collections = 1
                        versions.items = 1
                        versions.trash = 1
                        versions.searches = 1
                        versions.settings = 1
                        versions.deletions = 1
                        library?.versions = versions

                        let collection = RCollection()
                        collection.key = collectionKey
                        collection.name = "Locally deleted collection"
                        collection.version = 1
                        collection.deleted = true
                        collection.trash = true
                        collection.libraryId = .custom(.myLibrary)
                        realm.add(collection)

                        let item1 = RItem()
                        item1.key = "BBBBBBBB"
                        item1.baseTitle = "B"
                        item1.libraryId = .custom(.myLibrary)
                        realm.add(item1)

                        collection.items.append(item1)

                        let item2 = RItem()
                        item2.key = deletedItemKey
                        item2.baseTitle = "C"
                        item2.deleted = true
                        item2.trash = true
                        item2.libraryId = .custom(.myLibrary)
                        realm.add(item2)

                        collection.items.append(item2)
                    }

                    let versionResponses: [SyncObject: Any] = [.collection: [collectionKey: 2]]
                    let objectKeys: [SyncObject: String] = [.collection: collectionKey]
                    let libraryJson: [String: Any] = ["id": 0, "type": "user", "name": "A"]
                    let collectionData: [[String: Any]] = [["key": collectionKey, "version": 2, "library": libraryJson, "data": ["name": "A"]]]
                    let objectResponses: [SyncObject: Any] = [.collection: collectionData]

                    createStub(for: KeyRequest(), baseUrl: baseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys", withExtension: "json")!)
                    createStub(
                        for: SubmitDeletionsRequest(libraryId: libraryId, userId: self.userId, objectType: .collection, keys: [collectionKey], version: 1),
                        baseUrl: baseUrl,
                        headers: header,
                        statusCode: 412,
                        jsonResponse: [:] as [String: Any]
                    )
                    createStub(
                        for: SubmitDeletionsRequest(libraryId: libraryId, userId: self.userId, objectType: .item, keys: [deletedItemKey], version: 1),
                        baseUrl: baseUrl,
                        headers: header,
                        statusCode: 412,
                        jsonResponse: [:] as [String: Any]
                    )
                    createStub(for: GroupVersionsRequest(userId: self.userId), baseUrl: baseUrl, headers: header, jsonResponse: [:] as [String: Any])
                    objects.forEach { object in
                        createStub(
                            for: VersionsRequest(libraryId: libraryId, userId: self.userId, objectType: object, version: 1),
                            baseUrl: baseUrl,
                            headers: header,
                            jsonResponse: versionResponses[object] ?? [:] as [String: Any]
                        )
                    }
                    objects.forEach { object in
                        createStub(
                            for: ObjectsRequest(libraryId: libraryId, userId: self.userId, objectType: object, keys: (objectKeys[object] ?? "")),
                            baseUrl: baseUrl,
                            headers: header,
                            jsonResponse: objectResponses[object] ?? [:] as [String: Any]
                        )
                    }
                    createStub(
                        for: SettingsRequest(libraryId: libraryId, userId: self.userId, version: 1),
                        baseUrl: baseUrl,
                        headers: header,
                        jsonResponse: ["tagColors": ["value": [["name": "A", "color": "#CC66CC"]], "version": 1] as [String: Any]]
                    )
                    createStub(
                        for: DeletionsRequest(libraryId: libraryId, userId: self.userId, version: 1),
                        baseUrl: baseUrl,
                        headers: header,
                        jsonResponse: ["collections": [] as [Any], "searches": [] as [Any], "items": [] as [Any], "tags": [] as [Any]]
                    )

                    waitUntil(timeout: .seconds(10)) { doneAction in
                        self.syncController.reportFinish = { result in
                            switch result {
                            case .failure(let error):
                                fail("Failure: \(error)")

                            case .success(let data):
                                // precondition error should be reported first time, retry
                                guard let error = data.1.first as? Zotero.SyncError.NonFatal, case .preconditionFailed(let libraryId) = error else {
                                    fail("Failure: \(result)")
                                    return
                                }

                                self.syncController.reportFinish = { _ in
                                    let realm = try! Realm(configuration: self.realmConfig)
                                    realm.refresh()

                                    let library = realm.objects(RCustomLibrary.self).first
                                    expect(library?.type).to(equal(.myLibrary))

                                    let collections = realm.objects(RCollection.self).filter(.library(with: .custom(.myLibrary)))
                                    let items = realm.objects(RItem.self).filter(.library(with: .custom(.myLibrary)))

                                    expect(collections.count).to(equal(1))
                                    expect(items.count).to(equal(2))
                                    expect(realm.objects(RCollection.self).count).to(equal(1))
                                    expect(realm.objects(RItem.self).count).to(equal(2))

                                    let collection = realm.objects(RCollection.self).filter("key = %@", collectionKey).first
                                    expect(collection).toNot(beNil())
                                    expect(collection?.syncState).to(equal(.synced))
                                    expect(collection?.version).to(equal(2))
                                    expect(collection?.deleted).to(beFalse())
                                    expect(collection?.trash).to(beFalse())
                                    expect(collection?.customLibraryKey?.rawValue).to(equal(RCustomLibraryType.myLibrary.rawValue))
                                    expect(collection?.parentKey).to(beNil())
                                    expect(collection?.items.count).to(equal(2))
                                    if let collection = collection {
                                        expect(collection.items.map({ $0.key })).to(contain(["BBBBBBBB", "CCCCCCCC"]))
                                    }

                                    let item = realm.objects(RItem.self).filter("key = %@", "CCCCCCCC").first
                                    expect(item).toNot(beNil())
                                    expect(item?.deleted).to(beFalse())
                                    expect(item?.trash).to(beFalse())

                                    doneAction()
                                }

                                self.syncController.start(type: .prioritizeDownloads, libraries: .specific([libraryId]), retryAttempt: 4)
                            }
                        }

                        self.syncController.start(type: .normal, libraries: .all, retryAttempt: 0)
                    }
                }

                it("renames local file if remote filename changed") {
                    let header = ["last-modified-version": "3"]
                    let itemKey = "AAAAAAAA"
                    let libraryId = self.userLibraryId
                    let oldFilename = "filename"
                    let newFilename = "new filename"
                    let contentType = "text/plain"
                    let objects = SyncObject.allCases
                    let objectKeys: [SyncObject: String] = [.item: itemKey]
                    let versionResponses: [SyncObject: Any] = [.item: [itemKey: 3]]
                    let libraryJson: [String: Any] = ["id": 0, "type": "user", "name": "A"]
                    let objectResponses: [SyncObject: Any] = [
                        .item:
                            [
                                [
                                    "key": itemKey,
                                    "version": 3,
                                    "library": libraryJson,
                                    "data": ["title": "New title", "filename": newFilename, "contentType": contentType, "itemType": "attachment", "linkMode": LinkMode.importedFile.rawValue]
                                ] as [String: Any]
                            ]
                    ]

                    createStub(for: KeyRequest(), baseUrl: baseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys", withExtension: "json")!)
                    createStub(
                        for: SettingsRequest(libraryId: libraryId, userId: self.userId, version: 0),
                        baseUrl: baseUrl,
                        headers: header,
                        jsonResponse: ["tagColors": ["value": [] as [Any], "version": 3] as [String: Any]]
                    )
                    createStub(for: GroupVersionsRequest(userId: self.userId), baseUrl: baseUrl, headers: header, jsonResponse: [:] as [String: Any])
                    objects.forEach { object in
                        createStub(
                            for: VersionsRequest(libraryId: libraryId, userId: self.userId, objectType: object, version: 0),
                            baseUrl: baseUrl,
                            headers: header,
                            jsonResponse: versionResponses[object] ?? [:] as [String: Any]
                        )
                    }
                    objects.forEach { object in
                        createStub(
                            for: ObjectsRequest(libraryId: libraryId, userId: self.userId, objectType: object, keys: (objectKeys[object] ?? "")),
                            baseUrl: baseUrl,
                            headers: header,
                            jsonResponse: objectResponses[object] ?? [:] as [String: Any]
                        )
                    }
                    createStub(
                        for: DeletionsRequest(libraryId: libraryId, userId: self.userId, version: 0),
                        baseUrl: baseUrl,
                        headers: header,
                        jsonResponse: ["collections": [] as [Any], "searches": [] as [Any], "items": [] as [Any], "tags": [] as [Any]]
                    )

                    let file = Files.attachmentFile(in: libraryId, key: itemKey, filename: oldFilename, contentType: contentType)
                    let data = "file".data(using: .utf8)!
                    try! TestControllers.fileStorage.write(data, to: file, options: .atomic)

                    self.createNewSyncController()

                    let realm = self.realm!
                    try! realm.write {
                        let item = RItem()
                        item.key = itemKey
                        item.baseTitle = "Item"
                        item.rawType = ItemTypes.attachment
                        item.libraryId = .custom(.myLibrary)

                        let filenameField = RItemField()
                        filenameField.key = FieldKeys.Item.Attachment.filename
                        filenameField.value = oldFilename
                        item.fields.append(filenameField)

                        let contentTypeField = RItemField()
                        contentTypeField.key = FieldKeys.Item.Attachment.contentType
                        contentTypeField.value = contentType
                        item.fields.append(contentTypeField)

                        let linkModeField = RItemField()
                        linkModeField.key = FieldKeys.Item.Attachment.linkMode
                        linkModeField.value = LinkMode.importedFile.rawValue
                        item.fields.append(linkModeField)

                        realm.add(item)
                    }

                    waitUntil(timeout: .seconds(10)) { doneAction in
                        self.syncController.reportFinish = { _ in
                            let realm = try! Realm(configuration: self.realmConfig)
                            realm.refresh()

                            let item = realm.objects(RItem.self).filter(.key(itemKey, in: libraryId)).first
                            let filename = item?.fields.first(where: { $0.key == FieldKeys.Item.Attachment.filename })?.value
                            expect(filename).to(equal(newFilename))

                            let newFile = Files.attachmentFile(in: libraryId, key: itemKey, filename: newFilename, contentType: contentType)
                            expect(TestControllers.fileStorage.has(newFile)).to(beTrue())
                            expect(TestControllers.fileStorage.has(file)).to(beFalse())

                            try? TestControllers.fileStorage.remove(file)
                            try? TestControllers.fileStorage.remove(newFile)

                            doneAction()
                        }

                        self.syncController?.start(type: .normal, libraries: .all, retryAttempt: 0)
                    }
                }
            }

            describe("Upload") {
                it("should update collection and item") {
                    let oldVersion = 3
                    let newVersion = oldVersion + 1
                    let collectionKey = "AAAAAAAA"
                    let itemKey = "BBBBBBBB"

                    self.createNewSyncController()

                    try! self.realm.write {
                        let library = self.realm.object(ofType: RCustomLibrary.self, forPrimaryKey: RCustomLibraryType.myLibrary.rawValue)

                        let versions = RVersions()
                        versions.collections = oldVersion
                        versions.items = oldVersion
                        library?.versions = versions

                        let collection = RCollection()
                        collection.key = collectionKey
                        collection.name = "New name"
                        collection.version = oldVersion
                        collection.changes.append(RObjectChange.create(changes: RCollectionChanges.name))
                        collection.libraryId = .custom(.myLibrary)
                        self.realm.add(collection)

                        let item = RItem()
                        item.key = itemKey
                        item.syncState = .synced
                        item.version = oldVersion
                        item.changes.append(RObjectChange.create(changes: RItemChanges.fields))
                        item.libraryId = .custom(.myLibrary)
                        self.realm.add(item)

                        let titleField = RItemField()
                        titleField.key = "title"
                        titleField.value = "New item"
                        titleField.changed = true
                        item.fields.append(titleField)

                        let pageField = RItemField()
                        pageField.key = "numPages"
                        pageField.value = "1"
                        pageField.changed = true
                        item.fields.append(pageField)

                        let unchangedField = RItemField()
                        unchangedField.key = "callNumber"
                        unchangedField.value = "somenumber"
                        unchangedField.changed = false
                        item.fields.append(unchangedField)
                    }

                    let libraryId = self.userLibraryId

                    let collectionUpdate = UpdatesRequest(libraryId: libraryId, userId: self.userId, objectType: .collection, params: [], version: oldVersion)
                    // We don't care about specific params, we just want to catch update for all objecfts of this type
                    let collectionConditions = collectionUpdate.stubCondition(with: baseUrl, ignoreBody: true)
                    stub(condition: collectionConditions, response: { request -> HTTPStubsResponse in
                        let collectionResponseJson: [String: Any] = [
                            "key": collectionKey,
                            "version": newVersion,
                            "library": ["library": "user", "id": 123, "name": ""] as [String: Any],
                            "data": ["name": "New name", "isTrash": false] as [String: Any]
                        ]

                        let params = request.httpBodyStream.flatMap({ self.jsonParameters(from: $0) })
                        expect(params?.count).to(equal(1))
                        let firstParams = params?.first ?? [:]
                        expect(firstParams["key"] as? String).to(equal(collectionKey))
                        expect(firstParams["version"] as? Int).to(equal(oldVersion))
                        expect(firstParams["name"] as? String).to(equal("New name"))
                        return HTTPStubsResponse(
                            jsonObject: ["success": ["0": collectionKey], "successful": ["0": collectionResponseJson], "unchanged": [:] as [String: Any], "failed": [:] as [String: Any]],
                            statusCode: 200,
                            headers: ["last-modified-version": "\(newVersion)"]
                        )
                    })

                    let itemUpdate = UpdatesRequest(libraryId: libraryId, userId: self.userId, objectType: .item, params: [], version: oldVersion)
                    // We don't care about specific params, we just want to catch update for all objecfts of this type
                    let itemConditions = itemUpdate.stubCondition(with: baseUrl, ignoreBody: true)
                    stub(condition: itemConditions, response: { request -> HTTPStubsResponse in
                        let itemResponseJson = self.itemJson(key: itemKey, version: newVersion, type: "attachment")
                        let params = request.httpBodyStream.flatMap({ self.jsonParameters(from: $0) })
                        expect(params?.count).to(equal(1))
                        let firstParams = params?.first ?? [:]
                        expect(firstParams["key"] as? String).to(equal(itemKey))
                        expect(firstParams["version"] as? Int).to(equal(oldVersion))
                        expect(firstParams["title"] as? String).to(equal("New item"))
                        expect(firstParams["numPages"] as? String).to(equal("1"))
                        expect(firstParams["callNumber"]).to(beNil())
                        return HTTPStubsResponse(
                            jsonObject: ["success": ["0": itemKey] as [String: Any], "successful": ["0": itemResponseJson], "unchanged": [:] as [String: Any], "failed": [:] as [String: Any]],
                            statusCode: 200,
                            headers: ["last-modified-version": "\(newVersion)"]
                        )
                    })
                    createStub(for: KeyRequest(), baseUrl: baseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys", withExtension: "json")!)

                    waitUntil(timeout: .seconds(10)) { doneAction in
                        self.syncController.reportFinish = { _ in
                            let realm = try! Realm(configuration: self.realmConfig)
                            realm.refresh()

                            let library = realm.object(ofType: RCustomLibrary.self, forPrimaryKey: RCustomLibraryType.myLibrary.rawValue)

                            let versions = library?.versions
                            expect(versions?.collections).to(equal(newVersion))
                            expect(versions?.items).to(equal(newVersion))

                            let collection = realm.objects(RCollection.self).filter(.key(collectionKey, in: .custom(.myLibrary))).first
                            expect(collection?.version).to(equal(newVersion))
                            expect(collection?.changedFields.rawValue).to(equal(0))

                            let item = realm.objects(RItem.self).filter(.key(itemKey, in: .custom(.myLibrary))).first
                            expect(item?.version).to(equal(newVersion))
                            expect(item?.changedFields.rawValue).to(equal(0))
                            item?.fields.forEach({ field in
                                expect(field.changed).to(beFalse())
                            })

                            doneAction()
                        }
                        self.syncController.start(type: .normal, libraries: .specific([.custom(.myLibrary)]), retryAttempt: 0)
                    }
                }

                it("should upload child item after parent item") {
                    let oldVersion = 3
                    let newVersion = oldVersion + 1
                    let parentKey = "BBBBBBBB"
                    let childKey = "CCCCCCCC"
                    let otherKey = "AAAAAAAA"

                    self.createNewSyncController()

                    try! self.realm.write {
                        let library = self.realm.object(ofType: RCustomLibrary.self, forPrimaryKey: RCustomLibraryType.myLibrary.rawValue)

                        let versions = RVersions()
                        versions.collections = oldVersion
                        versions.items = oldVersion
                        library?.versions = versions

                        // Items created one after another, then CCCCCCCC has been updated and added
                        // as a child to BBBBBBBB, then AAAAAAAA has been updated and then BBBBBBBB has been updated
                        // AAAAAAAA is without a child, BBBBBBBB has child CCCCCCCC,
                        // BBBBBBBB has been updated after child CCCCCCCC, but BBBBBBBB should appear in parameters
                        // before CCCCCCCC because it is a parent

                        let allChanges: RItemChanges = [.fields, .creators, .parent, .trash, .relations, .tags, .collections, .type]

                        let item = RItem()
                        item.key = otherKey
                        item.syncState = .synced
                        item.version = oldVersion
                        item.changes.append(RObjectChange.create(changes: allChanges))
                        item.dateAdded = Date(timeIntervalSinceNow: -3600)
                        item.dateModified = Date(timeIntervalSinceNow: -1800)
                        item.libraryId = .custom(.myLibrary)
                        self.realm.add(item)

                        let item2 = RItem()
                        item2.key = parentKey
                        item2.syncState = .synced
                        item2.version = oldVersion
                        item2.changes.append(RObjectChange.create(changes: allChanges))
                        item2.dateAdded = Date(timeIntervalSinceNow: -3599)
                        item2.dateModified = Date(timeIntervalSinceNow: -60)
                        item2.libraryId = .custom(.myLibrary)
                        self.realm.add(item2)

                        let item3 = RItem()
                        item3.key = childKey
                        item3.syncState = .synced
                        item3.version = oldVersion
                        item3.changes.append(RObjectChange.create(changes: allChanges))
                        item3.dateAdded = Date(timeIntervalSinceNow: -3598)
                        item3.dateModified = Date(timeIntervalSinceNow: -3540)
                        item3.libraryId = .custom(.myLibrary)
                        item3.parent = item2
                        self.realm.add(item3)
                    }

                    let libraryId = self.userLibraryId

                    let update = UpdatesRequest(libraryId: libraryId, userId: self.userId, objectType: .item, params: [], version: oldVersion)
                    let conditions = update.stubCondition(with: baseUrl)
                    stub(condition: conditions, response: { request -> HTTPStubsResponse in
                        guard let params = request.httpBodyStream.flatMap({ self.jsonParameters(from: $0) }) else {
                            fail("parameters not found")
                            fatalError()
                        }

                        expect(params.count).to(equal(3))
                        let parentPos = params.firstIndex(where: { ($0["key"] as? String) == parentKey }) ?? -1
                        let childPos = params.firstIndex(where: { ($0["key"] as? String) == childKey }) ?? -1
                        expect(parentPos).toNot(equal(-1))
                        expect(childPos).toNot(equal(-1))
                        expect(parentPos).to(beLessThan(childPos))

                        return HTTPStubsResponse(
                            jsonObject: ["success": ["0": [:] as [String: Any]], "unchanged": [] as [Any], "failed": [] as [Any]] as [String: Any],
                            statusCode: 200,
                            headers: ["last-modified-version": "\(newVersion)"]
                        )
                    })
                    createStub(for: KeyRequest(), baseUrl: baseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys", withExtension: "json")!)

                    waitUntil(timeout: .seconds(10)) { doneAction in
                        self.syncController.reportFinish = { _ in
                            doneAction()
                        }
                        self.syncController.start(type: .normal, libraries: .specific([.custom(.myLibrary)]), retryAttempt: 0)
                    }
                }

                it("should upload child collection after parent collection") {
                    let oldVersion = 3
                    let newVersion = oldVersion + 1
                    let firstKey = "AAAAAAAA"
                    let secondKey = "BBBBBBBB"
                    let thirdKey = "CCCCCCCC"

                    self.createNewSyncController()

                    try! self.realm.write {
                        let library = self.realm.object(ofType: RCustomLibrary.self, forPrimaryKey: RCustomLibraryType.myLibrary.rawValue)

                        let versions = RVersions()
                        versions.collections = oldVersion
                        versions.items = oldVersion
                        library?.versions = versions

                        // Collections created in order: CCCCCCCC, BBBBBBBB, AAAAAAAA
                        // modified in order: BBBBBBBB, AAAAAAAA, CCCCCCCC
                        // but should be processed in order AAAAAAAA, BBBBBBBB, CCCCCCCC because A is a parent of B
                        // and B is a parent of C

                        let collection = RCollection()
                        let collection2 = RCollection()
                        let collection3 = RCollection()

                        self.realm.add(collection3)
                        self.realm.add(collection2)
                        self.realm.add(collection)

                        collection.key = firstKey
                        collection.syncState = .synced
                        collection.version = oldVersion
                        collection.changes.append(RObjectChange.create(changes: RCollectionChanges.all))
                        collection.dateModified = Date(timeIntervalSinceNow: -1800)
                        collection.libraryId = .custom(.myLibrary)

                        collection2.key = secondKey
                        collection2.syncState = .synced
                        collection2.version = oldVersion
                        collection2.changes.append(RObjectChange.create(changes: RCollectionChanges.all))
                        collection2.dateModified = Date(timeIntervalSinceNow: -3540)
                        collection2.libraryId = .custom(.myLibrary)
                        collection2.parentKey = collection.key

                        collection3.key = thirdKey
                        collection3.syncState = .synced
                        collection3.version = oldVersion
                        collection3.changes.append(RObjectChange.create(changes: RCollectionChanges.all))
                        collection3.dateModified = Date(timeIntervalSinceNow: -60)
                        collection3.libraryId = .custom(.myLibrary)
                        collection3.parentKey = collection2.key
                    }

                    let libraryId = self.userLibraryId

                    let update = UpdatesRequest(libraryId: libraryId, userId: self.userId, objectType: .collection, params: [], version: oldVersion)
                    let conditions = update.stubCondition(with: baseUrl)
                    stub(condition: conditions, response: { request -> HTTPStubsResponse in
                        guard let params = request.httpBodyStream.flatMap({ self.jsonParameters(from: $0) }) else {
                            fail("parameters not found")
                            fatalError()
                        }

                        expect(params.count).to(equal(3))
                        expect(params[0]["key"] as? String).to(equal(firstKey))
                        expect(params[1]["key"] as? String).to(equal(secondKey))
                        expect(params[2]["key"] as? String).to(equal(thirdKey))

                        return HTTPStubsResponse(
                            jsonObject: ["success": ["0": [:] as [String: Any]], "unchanged": [] as [Any], "failed": [] as [Any]] as [String: Any],
                            statusCode: 200,
                            headers: ["last-modified-version": "\(newVersion)"]
                        )
                    })
                    createStub(for: KeyRequest(), baseUrl: baseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys", withExtension: "json")!)

                    self.createNewSyncController()

                    waitUntil(timeout: .seconds(10)) { doneAction in
                        self.syncController.reportFinish = { _ in
                            doneAction()
                        }
                        self.syncController.start(type: .normal, libraries: .specific([.custom(.myLibrary)]), retryAttempt: 0)
                    }
                }

                it("should update library version after upload") {
                    let oldVersion = 3
                    let newVersion = oldVersion + 10

                    self.createNewSyncController()

                    try! self.realm.write {
                        let library = self.realm.object(ofType: RCustomLibrary.self, forPrimaryKey: RCustomLibraryType.myLibrary.rawValue)

                        let versions = RVersions()
                        versions.collections = oldVersion
                        versions.items = oldVersion
                        library?.versions = versions

                        let collection = RCollection()
                        self.realm.add(collection)

                        collection.key = "AAAAAAAA"
                        collection.syncState = .synced
                        collection.version = oldVersion
                        collection.changes.append(RObjectChange.create(changes: RCollectionChanges.all))
                        collection.dateModified = Date()
                        collection.libraryId = .custom(.myLibrary)
                    }

                    let libraryId = self.userLibraryId

                    let update = UpdatesRequest(libraryId: libraryId, userId: self.userId, objectType: .collection, params: [], version: oldVersion)
                    createStub(for: KeyRequest(), baseUrl: baseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys", withExtension: "json")!)
                    // We don't care about specific post params, we just need to catch all updates for given type
                    createStub(
                        for: update,
                        ignoreBody: true,
                        baseUrl: baseUrl,
                        headers: ["last-modified-version": "\(newVersion)"],
                        statusCode: 200,
                        jsonResponse: ["success": ["0": [:] as [String: Any]], "unchanged": [] as [Any], "failed": [] as [Any]] as [String: Any]
                    )

                    waitUntil(timeout: .seconds(10)) { doneAction in
                        self.syncController.reportFinish = { _ in
                            let realm = try! Realm(configuration: self.realmConfig)
                            realm.refresh()

                            let library = realm.object(ofType: RCustomLibrary.self, forPrimaryKey: RCustomLibraryType.myLibrary.rawValue)

                            expect(library?.versions?.collections).to(equal(newVersion))

                            doneAction()
                        }
                        self.syncController.start(type: .normal, libraries: .specific([.custom(.myLibrary)]), retryAttempt: 0)
                    }
                }

                it("should process downloads after upload failure") {
                    let header = ["last-modified-version": "3"]
                    let libraryId = self.userLibraryId
                    let objects = SyncObject.allCases

                    var downloadCalled = false

                    var statusCode: Int32 = 412
                    let request = UpdatesRequest(libraryId: libraryId, userId: self.userId, objectType: .item, params: [], version: 0)
                    stub(condition: request.stubCondition(with: baseUrl), response: { _ -> HTTPStubsResponse in
                        let code = statusCode
                        statusCode = 200
                        return HTTPStubsResponse(jsonObject: [:] as [String: Any], statusCode: code, headers: header)
                    })
                    createStub(for: GroupVersionsRequest(userId: self.userId), baseUrl: baseUrl, headers: header, jsonResponse: [:] as [String: Any])
                    objects.forEach { object in
                        createStub(
                            for: VersionsRequest(libraryId: libraryId, userId: self.userId, objectType: object, version: 0),
                            baseUrl: baseUrl,
                            headers: header,
                            jsonResponse: [:] as [String: Any]
                        )
                    }
                    stub(condition: SettingsRequest(libraryId: libraryId, userId: self.userId, version: 0).stubCondition(with: baseUrl),
                         response: { _ -> HTTPStubsResponse in
                        downloadCalled = true
                        return HTTPStubsResponse(jsonObject: [:] as [String: Any], statusCode: 200, headers: header)
                    })
                    createStub(for: KeyRequest(), baseUrl: baseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys", withExtension: "json")!)
                    createStub(
                        for: DeletionsRequest(libraryId: libraryId, userId: self.userId, version: 0),
                        baseUrl: baseUrl,
                        headers: header,
                        jsonResponse: ["collections": [] as [Any], "searches": [] as [Any], "items": [] as [Any], "tags": [] as [Any]]
                    )

                    self.createNewSyncController()

                    try! self.realm.write {
                        let item = RItem()
                        self.realm.add(item)

                        item.key = "AAAAAAAA"
                        item.syncState = .synced
                        item.version = 2
                        item.trash = true
                        item.changes.append(RObjectChange.create(changes: RItemChanges.trash))
                        item.dateModified = Date()
                        item.libraryId = .custom(.myLibrary)
                    }

                    waitUntil(timeout: .seconds(1000)) { doneAction in
                        self.syncController.reportFinish = { result in
                            switch result {
                            case .failure(let error):
                                fail("Failure: \(error)")

                            case .success(let data):
                                // precondition error should be reported first time, retry
                                guard let error = data.1.first as? Zotero.SyncError.NonFatal, case .preconditionFailed(let libraryId) = error else {
                                    fail("Failure: \(result)")
                                    return
                                }

                                self.syncController.reportFinish = { _ in
                                    expect(downloadCalled).to(beTrue())
                                    doneAction()
                                }

                                self.syncController.start(type: .prioritizeDownloads, libraries: .specific([libraryId]), retryAttempt: 4)
                            }
                        }

                        self.syncController.start(type: .normal, libraries: .all, retryAttempt: 0)
                    }
                }

                it("should download remote file after file upload failure") {
                    let header = ["last-modified-version": "3"]
                    let libraryId = self.userLibraryId
                    let objects = SyncObject.allCases
                    let key = "AAAAAAAA"
                    let filename = "doc.txt"
                    let data = "test string".data(using: .utf8)!
                    let file = Files.attachmentFile(in: libraryId, key: key, filename: filename, contentType: "text/plain")
                    try! FileStorageController().write(data, to: file, options: .atomicWrite)
                    let fileMd5 = md5(from: file.createUrl())!

                    var didCallDownload = false

                    createStub(
                        for: AuthorizeUploadRequest(libraryId: libraryId, userId: self.userId, key: key, filename: filename, filesize: UInt64(data.count), md5: fileMd5, mtime: 123, oldMd5: nil),
                        ignoreBody: true,
                        baseUrl: baseUrl,
                        statusCode: 412,
                        jsonResponse: [:] as [String: Any]
                    )
                    createStub(
                        for: UpdatesRequest(libraryId: libraryId, userId: self.userId, objectType: .item, params: [], version: 0),
                        baseUrl: baseUrl,
                        headers: header,
                        jsonResponse: [:] as [String: Any]
                    )
                    createStub(for: GroupVersionsRequest(userId: self.userId), baseUrl: baseUrl, headers: header, jsonResponse: [:] as [String: Any])
                    objects.forEach { object in
                        createStub(
                            for: VersionsRequest(libraryId: libraryId, userId: self.userId, objectType: object, version: 0),
                            baseUrl: baseUrl,
                            headers: header,
                            jsonResponse: [:] as [String: Any]
                        )
                    }
                    createStub(for: SettingsRequest(libraryId: libraryId, userId: self.userId, version: 0), baseUrl: baseUrl, headers: header, jsonResponse: [:] as [String: Any])
                    createStub(for: KeyRequest(), baseUrl: baseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys", withExtension: "json")!)
                    createStub(
                        for: DeletionsRequest(libraryId: libraryId, userId: self.userId, version: 0),
                        baseUrl: baseUrl,
                        headers: header,
                        jsonResponse: ["collections": [] as [Any], "searches": [] as [Any], "items": [] as [Any], "tags": [] as [Any]]
                    )
                    stub(condition: FileRequest(libraryId: libraryId, userId: self.userId, key: key, destination: file).stubCondition(with: baseUrl), response: { _ -> HTTPStubsResponse in
                        didCallDownload = true
                        return HTTPStubsResponse(data: data, statusCode: 200, headers: header)
                    })

                    self.createNewSyncController()

                    try! self.realm.write {
                        let item = RItem()
                        item.key = key
                        item.rawType = "attachment"
                        item.customLibraryKey = .myLibrary
                        item.attachmentNeedsSync = true

                        let contentField = RItemField()
                        contentField.key = FieldKeys.Item.Attachment.contentType
                        contentField.value = "text/plain"
                        item.fields.append(contentField)

                        let filenameField = RItemField()
                        filenameField.key = FieldKeys.Item.Attachment.filename
                        filenameField.value = filename
                        item.fields.append(filenameField)

                        let linkModeField = RItemField()
                        linkModeField.key = FieldKeys.Item.Attachment.linkMode
                        linkModeField.value = LinkMode.importedFile.rawValue
                        item.fields.append(linkModeField)

                        let md5Field = RItemField()
                        md5Field.key = FieldKeys.Item.Attachment.md5
                        md5Field.value = "md5hash1"
                        item.fields.append(md5Field)

                        let mtimeField = RItemField()
                        mtimeField.key = FieldKeys.Item.Attachment.mtime
                        mtimeField.value = "100"
                        item.fields.append(mtimeField)

                        self.realm.add(item)
                    }

                    waitUntil(timeout: .seconds(10)) { doneAction in
                        self.syncController.reportFinish = { _ in
                            expect(didCallDownload).to(beTrue())

                            let realm = try! Realm(configuration: self.realmConfig)
                            realm.refresh()

                            let item = realm.objects(RItem.self).filter(.key(key, in: libraryId)).first
                            expect(item?.attachmentNeedsSync).to(beFalse())
                            
                            try? FileStorageController().remove(file)

                            doneAction()
                        }

                        self.syncController.start(type: .normal, libraries: .all, retryAttempt: 0)
                    }
                }

                it("should upload local deletions") {
                    let header = ["last-modified-version": "1"]
                    let libraryId = self.userLibraryId
                    let collectionKey = "AAAAAAAA"
                    let searchKey = "BBBBBBBB"
                    let itemKey = "CCCCCCCC"

                    self.createNewSyncController()

                    try! self.realm.write {
                        let library = self.realm.object(ofType: RCustomLibrary.self, forPrimaryKey: RCustomLibraryType.myLibrary.rawValue)

                        let versions = RVersions()
                        library?.versions = versions

                        let collection = RCollection()
                        collection.key = collectionKey
                        collection.name = "Deleted collection"
                        collection.version = 0
                        collection.deleted = true
                        collection.libraryId = .custom(.myLibrary)
                        self.realm.add(collection)

                        let item = RItem()
                        item.key = itemKey
                        item.baseTitle = "Deleted item"
                        item.deleted = true
                        item.libraryId = .custom(.myLibrary)
                        self.realm.add(item)

                        collection.items.append(item)

                        let search = RSearch()
                        search.key = searchKey
                        search.name = "Deleted search"
                        search.deleted = true
                        search.libraryId = .custom(.myLibrary)
                        self.realm.add(search)
                    }

                    createStub(for: KeyRequest(), baseUrl: baseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys", withExtension: "json")!)
                    createStub(for: GroupVersionsRequest(userId: self.userId), baseUrl: baseUrl, headers: header, jsonResponse: [:] as [String: Any])
                    createStub(
                        for: SubmitDeletionsRequest(libraryId: libraryId, userId: self.userId, objectType: .collection, keys: [collectionKey], version: 0),
                        baseUrl: baseUrl,
                        headers: header,
                        jsonResponse: [:] as [String: Any]
                    )
                    createStub(
                        for: SubmitDeletionsRequest(libraryId: libraryId, userId: self.userId, objectType: .search, keys: [searchKey], version: 0),
                        baseUrl: baseUrl,
                        headers: header,
                        jsonResponse: [:] as [String: Any]
                    )
                    createStub(
                        for: SubmitDeletionsRequest(libraryId: libraryId, userId: self.userId, objectType: .item, keys: [itemKey], version: 0),
                        baseUrl: baseUrl,
                        headers: header,
                        jsonResponse: [:] as [String: Any]
                    )

                    waitUntil(timeout: .seconds(10)) { doneAction in
                        self.syncController.reportFinish = { _ in
                            let realm = try! Realm(configuration: self.realmConfig)
                            realm.refresh()

                            expect(realm.objects(RCollection.self).count).to(equal(0))
                            expect(realm.objects(RSearch.self).count).to(equal(0))
                            expect(realm.objects(RItem.self).count).to(equal(0))

                            let collection = realm.objects(RCollection.self).filter("key = %@", collectionKey).first
                            expect(collection).to(beNil())
                            let search = realm.objects(RSearch.self).filter("key = %@", searchKey).first
                            expect(search).to(beNil())
                            let item = realm.objects(RItem.self).filter("key = %@", itemKey).first
                            expect(item).to(beNil())

                            doneAction()
                        }

                        self.syncController.start(type: .normal, libraries: .all, retryAttempt: 0)
                    }
                }

                // TODO: Enable when proper CR is implemented
//                it("should delay on second upload conflict") {
//                    let header = ["last-modified-version" : "3"]
//                    let libraryId = self.userLibraryId
//                    let itemToDelete = "DDDDDDDD"
//                    let objects = SyncObject.allCases
//
//                    let realm = self.realm
//                    try! realm.write {
//                        let myLibrary = self.realm.objects(RCustomLibrary.self).first
//                        let item = RItem()
//                        item.key = itemToDelete
//                        item.title = "Delete me"
//                        item.changedFields = .fields
//                        item.customLibrary = myLibrary
//                        realm.add(item)
//                    }
//
//                    let predicate = Predicates.key(itemToDelete, in: .custom(.myLibrary))
//                    let toBeDeletedItem = realm.objects(RItem.self).filter(predicate).first
//                    expect(toBeDeletedItem).toNot(beNil())
//
//                    var retryCount = 0
//                    let request = UpdatesRequest(libraryId: libraryId, userId: self.userId, objectType: .item, params: [], version: 0)
//                    // We don't care about specific params, we just need to count all update requests
//                    let condition = request.stubCondition(with: baseUrl, ignorePostParams: true)
//                    stub(condition: condition, response: { _ -> HTTPStubsResponse in
//                        retryCount += 1
//                        return HTTPStubsResponse(jsonObject: [:], statusCode: (retryCount <= 2 ? 412 : 200), headers: header)
//                    })
//                    objects.forEach { object in
//                        let version: Int? = object == .group ? nil : 0
//                        createStub(for: VersionsRequest(libraryId: libraryId, userId: self.userId,
//                                                                     objectType: object, version: version),
//                                        baseUrl: baseUrl, headers: header,
//                                        response: [:])
//                    }
//                    createStub(for: KeyRequest(), baseUrl: baseUrl, response: ["access": ["":""]])
//                    createStub(for: SettingsRequest(libraryId: libraryId, userId: self.userId, version: 0),
//                                    baseUrl: baseUrl, headers: header,
//                                    response: ["tagColors" : ["value": [], "version": 2]])
//                    createStub(for: DeletionsRequest(libraryId: libraryId, userId: self.userId, version: 0),
//                                    baseUrl: baseUrl, headers: header,
//                                    response: ["collections": [], "searches": [], "items": [itemToDelete], "tags": []])
//
//                    var lastDelay: Int?
//                    self.controller = SyncController(userId: self.userId,
//                                                     handler: self.syncHandler,
//                                                     conflictDelays: self.delays)
//                    self.controller?.reportDelay = { delay in
//                        lastDelay = delay
//                    }
//
//                    waitUntil(timeout: 10) { doneAction in
//                        self.controller?.reportFinish = { _ in
//                            expect(lastDelay).to(equal(1))
//                            expect(retryCount).to(equal(3))
//
//                            let realm = try! Realm(configuration: self.realmConfig)
//                            realm.refresh()
//
//                            let predicate = Predicates.key(itemToDelete, in: .custom(.myLibrary))
//                            let deletedItem = realm.objects(RItem.self).filter(predicate).first
//                            expect(deletedItem).toNot(beNil())
//
//                            doneAction()
//                        }
//                        self.controller?.start(type: .normal, libraries: .all)
//                    }
//                }
            }

            describe("full sync") {
                it("should make only one request if in sync") {
                    let libraryId = self.userLibraryId
                    let expected: [SyncController.Action] = [
                        .loadKeyPermissions,
                        .syncGroupVersions,
                        .createLibraryActions(.all, .automatic),
                        .syncSettings(libraryId, 0),
                        .syncVersions(libraryId: .custom(.myLibrary), object: .collection, version: 0, checkRemote: false),
                        .syncVersions(libraryId: .custom(.myLibrary), object: .search, version: 0, checkRemote: false),
                        .syncVersions(libraryId: .custom(.myLibrary), object: .item, version: 0, checkRemote: false),
                        .syncVersions(libraryId: .custom(.myLibrary), object: .trash, version: 0, checkRemote: false)
                    ]

                    createStub(for: KeyRequest(), baseUrl: baseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys", withExtension: "json")!)
                    createStub(for: GroupVersionsRequest(userId: self.userId), baseUrl: baseUrl, headers: nil, statusCode: 200, jsonResponse: [:] as [String: Any])
                    createStub(for: SettingsRequest(libraryId: libraryId, userId: self.userId, version: 0), baseUrl: baseUrl, statusCode: 304, jsonResponse: [:] as [String: Any])

                    self.createNewSyncController()

                    waitUntil(timeout: .seconds(10)) { doneAction in
                        self.syncController.reportFinish = { result in
                            switch result {
                            case .success(let data):
                                expect(data.0).to(equal(expected))

                            case .failure(let error):
                                fail("Failure: \(error)")
                            }

                            doneAction()
                        }

                        self.syncController.start(type: .normal, libraries: .all, retryAttempt: 0)
                    }
                }

                it("should download missing/updated local objects and flag remotely missing local objects for upload") {
                    let libraryId = self.userLibraryId
                    let oldVersion = 3
                    let newVersion = 5
                    let outdatedKey = "AAAAAAAA"
                    let locallyMissingKey = "BBBBBBBB"
                    let remotelyMissingKey = "CCCCCCCC"
                    let tagName = "Tag name"
                    let oldColor = "#ffffff"
                    let newColor = "#000000"
                    let header = ["last-modified-version": "\(newVersion)"]

                    let libraryJson: [String: Any] = ["id": 0, "type": "user", "name": "A"]
                    let dataAJson: [String: Any] = ["title": "A", "itemType": "book", "collections": [] as [String], "tags": [["tag": tagName]]]
                    let dataBJson: [String: Any] = ["title": "B", "itemType": "thesis", "collections": [] as [String]]
                    let objectResponse: [[String: Any]] = [["key": outdatedKey, "version": newVersion, "library": libraryJson, "data": dataAJson],
                                                           ["key": locallyMissingKey, "version": newVersion, "library": libraryJson, "data": dataBJson]]

                    SyncObject.allCases.forEach { object in
                        if object == .item {
                            createStub(
                                for: VersionsRequest(libraryId: libraryId, userId: self.userId, objectType: object, version: 0),
                                baseUrl: baseUrl,
                                headers: header,
                                jsonResponse: [outdatedKey: newVersion, locallyMissingKey: newVersion]
                            )
                        } else {
                            createStub(
                                for: VersionsRequest(libraryId: libraryId, userId: self.userId, objectType: object, version: 0),
                                baseUrl: baseUrl,
                                headers: header,
                                jsonResponse: [:] as [String: Any]
                            )
                        }
                    }
                    createStub(for: KeyRequest(), baseUrl: baseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys", withExtension: "json")!)
                    createStub(for: GroupVersionsRequest(userId: self.userId), baseUrl: baseUrl, headers: nil, statusCode: 200, jsonResponse: [:] as [String: Any])
                    createStub(
                        for: ObjectsRequest(libraryId: libraryId, userId: self.userId, objectType: .item, keys: "\(outdatedKey),\(locallyMissingKey)"),
                        baseUrl: baseUrl,
                        headers: header,
                        jsonResponse: objectResponse
                    )
                    createStub(
                        for: SettingsRequest(libraryId: libraryId, userId: self.userId, version: 0),
                        baseUrl: baseUrl,
                        headers: header,
                        jsonResponse: ["tagColors": ["value": [["name": tagName, "color": newColor]], "version": newVersion] as [String: Any]]
                    )
                    createStub(
                        for: DeletionsRequest(libraryId: libraryId, userId: self.userId, version: 0),
                        baseUrl: baseUrl,
                        headers: header,
                        jsonResponse: ["collections": [], "searches": [], "items": [], "tags": [] as [String]]
                    )

                    self.createNewSyncController()

                    try! self.realm.write {
                        let library = self.realm.object(ofType: RCustomLibrary.self, forPrimaryKey: RCustomLibraryType.myLibrary.rawValue)

                        let versions = RVersions()
                        versions.collections = newVersion
                        versions.items = newVersion
                        versions.deletions = newVersion
                        versions.searches = newVersion
                        versions.settings = newVersion
                        versions.trash = newVersion
                        library?.versions = versions

                        let tag = RTag()
                        tag.name = tagName
                        tag.color = oldColor
                        tag.libraryId = .custom(.myLibrary)

                        let outdatedItem = RItem()
                        outdatedItem.key = outdatedKey
                        outdatedItem.rawType = "thesis"
                        outdatedItem.syncState = .synced
                        outdatedItem.version = oldVersion
                        outdatedItem.dateAdded = Date(timeIntervalSinceNow: -3600)
                        outdatedItem.dateModified = Date(timeIntervalSinceNow: -1800)
                        outdatedItem.libraryId = .custom(.myLibrary)
                        self.realm.add(outdatedItem)

                        let typedTag = RTypedTag()
                        typedTag.type = .automatic
                        self.realm.add(typedTag)
                        typedTag.tag = tag
                        typedTag.item = outdatedItem

                        let remotelyMissingItem = RItem()
                        remotelyMissingItem.key = remotelyMissingKey
                        remotelyMissingItem.syncState = .synced
                        remotelyMissingItem.version = newVersion
                        remotelyMissingItem.dateAdded = Date(timeIntervalSinceNow: -3599)
                        remotelyMissingItem.dateModified = Date(timeIntervalSinceNow: -60)
                        remotelyMissingItem.libraryId = .custom(.myLibrary)
                        self.realm.add(remotelyMissingItem)
                    }

                    waitUntil(timeout: .seconds(10)) { doneAction in
                        self.syncController.reportFinish = { result in
                            switch result {
                            case .success:
                                let realm = try! Realm(configuration: self.realmConfig)
                                realm.refresh()

                                let outdatedItem = realm.objects(RItem.self).filter(.key(outdatedKey)).first
                                expect(outdatedItem?.version).to(equal(newVersion))
                                expect(outdatedItem?.syncState).to(equal(.synced))
                                expect(outdatedItem?.rawType).to(equal("book"))
                                expect(outdatedItem?.tags.first?.tag?.color).to(equal(newColor))

                                let locallyMissingItem = realm.objects(RItem.self).filter(.key(locallyMissingKey)).first
                                expect(locallyMissingItem?.version).to(equal(newVersion))
                                expect(locallyMissingItem?.syncState).to(equal(.synced))
                                expect(locallyMissingItem?.rawType).to(equal("thesis"))

                                let remotelyMissingItem = realm.objects(RItem.self).filter(.key(remotelyMissingKey)).first
                                expect(remotelyMissingItem?.changedFields).toNot(be([] as [String]))

                            case .failure(let error):
                                fail("Failure: \(error)")
                            }

                            doneAction()
                        }

                        self.syncController.start(type: .full, libraries: .all, retryAttempt: 0)
                    }
                }

                it("should reprocess remote deletions") {
                    let libraryId = self.userLibraryId
                    let newVersion = 5
                    let syncedKey = "AAAAAAAA"
                    let changedKey = "BBBBBBBB"
                    let header = ["last-modified-version": "\(newVersion)"]

                    SyncObject.allCases.forEach { object in
                        createStub(
                            for: VersionsRequest(libraryId: libraryId, userId: self.userId, objectType: object, version: 0),
                            baseUrl: baseUrl,
                            headers: header,
                            jsonResponse: [:] as [String: Any]
                        )
                    }
                    createStub(for: KeyRequest(), baseUrl: baseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys", withExtension: "json")!)
                    createStub(for: GroupVersionsRequest(userId: self.userId), baseUrl: baseUrl, headers: nil, statusCode: 200, jsonResponse: [:] as [String: Any])
                    createStub(for: SettingsRequest(libraryId: libraryId, userId: self.userId, version: 0), baseUrl: baseUrl, headers: header, jsonResponse: [:] as [String: Any])
                    createStub(
                        for: DeletionsRequest(libraryId: libraryId, userId: self.userId, version: 0),
                        baseUrl: baseUrl,
                        headers: header,
                        jsonResponse: ["collections": [], "searches": [], "items": [syncedKey, changedKey], "tags": []]
                    )

                    self.createNewSyncController()

                    try! self.realm.write {
                        let library = self.realm.object(ofType: RCustomLibrary.self, forPrimaryKey: RCustomLibraryType.myLibrary.rawValue)

                        let versions = RVersions()
                        versions.collections = newVersion
                        versions.items = newVersion
                        versions.deletions = newVersion
                        versions.searches = newVersion
                        versions.settings = newVersion
                        versions.trash = newVersion
                        library?.versions = versions

                        let syncedItem = RItem()
                        syncedItem.key = syncedKey
                        syncedItem.rawType = "thesis"
                        syncedItem.syncState = .synced
                        syncedItem.version = newVersion
                        syncedItem.dateAdded = Date(timeIntervalSinceNow: -3600)
                        syncedItem.dateModified = Date(timeIntervalSinceNow: -1800)
                        syncedItem.libraryId = .custom(.myLibrary)
                        self.realm.add(syncedItem)

                        let changedItem = RItem()
                        changedItem.key = changedKey
                        changedItem.rawType = "thesis"
                        changedItem.syncState = .synced
                        changedItem.changes.append(RObjectChange.create(changes: RItemChanges.type))
                        changedItem.version = newVersion
                        changedItem.dateAdded = Date(timeIntervalSinceNow: -3600)
                        changedItem.dateModified = Date(timeIntervalSinceNow: -1800)
                        changedItem.libraryId = .custom(.myLibrary)
                        self.realm.add(changedItem)

                        let field = RItemField()
                        field.key = "place"
                        field.value = "value"
                        field.changed = false
                        changedItem.fields.append(field)
                    }

                    waitUntil(timeout: .seconds(10)) { doneAction in
                        self.syncController.reportFinish = { result in
                            switch result {
                            case .success:
                                let realm = try! Realm(configuration: self.realmConfig)
                                realm.refresh()

                                // Synced item should be deleted
                                let syncedItem = realm.objects(RItem.self).filter(.key(syncedKey)).first
                                expect(syncedItem).to(beNil())
                                // Locally changed item should be restored
                                let changedItem = realm.objects(RItem.self).filter(.key(changedKey)).first
                                expect(changedItem).toNot(beNil())
                                expect(changedItem?.fields.first?.changed).to(beTrue())

                            case .failure(let error):
                                fail("Failure: \(error)")
                            }

                            doneAction()
                        }

                        self.syncController.start(type: .full, libraries: .all, retryAttempt: 0)
                    }
                }

                it("should check for remote changes if all write actions failed before reaching zotero backend") {
                    let libraryId = self.userLibraryId
                    let key = "AAAAAAAA"
                    let filename = "doc2.txt"
                    let file = Files.attachmentFile(in: libraryId, key: key, filename: filename, contentType: "text/plain")
                    let expected: [SyncController.Action] = [
                        .loadKeyPermissions,
                        .syncGroupVersions,
                        .createLibraryActions(.all, .automatic),
                        .createUploadActions(libraryId: libraryId, hadOtherWriteActions: false, canEditFiles: true),
                        .uploadAttachment(AttachmentUpload(libraryId: libraryId, key: key, filename: filename, contentType: "text/plain", md5: "somemd5hash", mtime: 1000, file: file, oldMd5: nil)),
                        .createLibraryActions(.specific([libraryId]), .onlyDownloads),
                        .syncSettings(libraryId, 0),
                        .syncVersions(libraryId: libraryId, object: .collection, version: 0, checkRemote: false),
                        .syncVersions(libraryId: libraryId, object: .search, version: 0, checkRemote: false),
                        .syncVersions(libraryId: libraryId, object: .item, version: 0, checkRemote: false),
                        .syncVersions(libraryId: libraryId, object: .trash, version: 0, checkRemote: false)
                    ]

                    createStub(for: KeyRequest(), baseUrl: baseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys", withExtension: "json")!)
                    createStub(for: GroupVersionsRequest(userId: self.userId), baseUrl: baseUrl, headers: nil, statusCode: 200, jsonResponse: [:] as [String: Any])
                    createStub(for: SettingsRequest(libraryId: libraryId, userId: self.userId, version: 0), baseUrl: baseUrl, statusCode: 304, jsonResponse: [:] as [String: Any])

                    self.createNewSyncController()

                    try! self.realm.write {
                        let item = RItem()
                        item.key = key
                        item.rawType = "attachment"
                        item.customLibraryKey = .myLibrary
                        item.attachmentNeedsSync = true

                        let contentField = RItemField()
                        contentField.key = FieldKeys.Item.Attachment.contentType
                        contentField.value = "text/plain"
                        item.fields.append(contentField)

                        let filenameField = RItemField()
                        filenameField.key = FieldKeys.Item.Attachment.filename
                        filenameField.value = filename
                        item.fields.append(filenameField)

                        let linkModeField = RItemField()
                        linkModeField.key = FieldKeys.Item.Attachment.linkMode
                        linkModeField.value = LinkMode.importedFile.rawValue
                        item.fields.append(linkModeField)

                        let mtimeField = RItemField()
                        mtimeField.key = FieldKeys.Item.Attachment.mtime
                        mtimeField.value = "1000"
                        item.fields.append(mtimeField)

                        let md5Field = RItemField()
                        md5Field.key = FieldKeys.Item.Attachment.md5
                        md5Field.value = "somemd5hash"
                        item.fields.append(md5Field)

                        self.realm.add(item)
                    }

                    waitUntil(timeout: .seconds(10)) { doneAction in
                        self.syncController.reportFinish = { result in
                            switch result {
                            case .success(let data):
                                expect(data.0).to(equal(expected))

                            case .failure(let error):
                                fail("Failure: \(error)")
                            }

                            doneAction()
                        }

                        self.syncController.start(type: .normal, libraries: .all, retryAttempt: 0)
                    }
                }

                it("should check for remote changes if all upload actions are ongoing in background and no other write actions were performed before") {
                    let libraryId = self.userLibraryId
                    let key = "AAAAAAAA"
                    let filename = "doc2.txt"
                    let file = Files.attachmentFile(in: libraryId, key: key, filename: filename, contentType: "text/plain")
                    let fileMd5 = "md5hash"
                    let expected: [SyncController.Action] = [
                        .loadKeyPermissions,
                        .syncGroupVersions,
                        .createLibraryActions(.all, .automatic),
                        .createUploadActions(libraryId: libraryId, hadOtherWriteActions: false, canEditFiles: true),
                        .createLibraryActions(.specific([libraryId]), .onlyDownloads),
                        .syncSettings(libraryId, 0),
                        .syncVersions(libraryId: libraryId, object: .collection, version: 0, checkRemote: false),
                        .syncVersions(libraryId: libraryId, object: .search, version: 0, checkRemote: false),
                        .syncVersions(libraryId: libraryId, object: .item, version: 0, checkRemote: false),
                        .syncVersions(libraryId: libraryId, object: .trash, version: 0, checkRemote: false)
                    ]

                    createStub(for: KeyRequest(), baseUrl: baseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys", withExtension: "json")!)
                    createStub(for: GroupVersionsRequest(userId: self.userId), baseUrl: baseUrl, headers: nil, statusCode: 200, jsonResponse: [:] as [String: Any])
                    createStub(for: SettingsRequest(libraryId: libraryId, userId: self.userId, version: 0), baseUrl: baseUrl, statusCode: 304, jsonResponse: [:] as [String: Any])

                    self.createNewSyncController()

                    let taskId = 1
                    let backgroundUpload = BackgroundUpload(
                        type: .zotero(uploadKey: "abc"),
                        key: key,
                        libraryId: libraryId,
                        userId: self.userId,
                        remoteUrl: URL(string: "https://zotero.org/")!,
                        fileUrl: file.createUrl(),
                        md5: fileMd5,
                        date: Date(),
                        completion: nil
                    )
                    let backgroundContext = BackgroundUploaderContext()
                    backgroundContext.save(upload: backgroundUpload, taskId: taskId)

                    try! self.realm.write {
                        let item = RItem()
                        item.key = key
                        item.rawType = "attachment"
                        item.customLibraryKey = .myLibrary
                        item.attachmentNeedsSync = true

                        let contentField = RItemField()
                        contentField.key = FieldKeys.Item.Attachment.contentType
                        contentField.value = "text/plain"
                        item.fields.append(contentField)

                        let filenameField = RItemField()
                        filenameField.key = FieldKeys.Item.Attachment.filename
                        filenameField.value = filename
                        item.fields.append(filenameField)

                        let linkModeField = RItemField()
                        linkModeField.key = FieldKeys.Item.Attachment.linkMode
                        linkModeField.value = LinkMode.importedFile.rawValue
                        item.fields.append(linkModeField)

                        let md5Field = RItemField()
                        md5Field.key = FieldKeys.Item.Attachment.md5
                        md5Field.value = fileMd5
                        item.fields.append(md5Field)

                        self.realm.add(item)
                    }

                    waitUntil(timeout: .seconds(10)) { doneAction in
                        self.syncController.reportFinish = { result in
                            switch result {
                            case .success(let data):
                                expect(data.0).to(equal(expected))

                            case .failure(let error):
                                fail("Failure: \(error)")
                            }

                            backgroundContext.deleteUpload(with: taskId)

                            doneAction()
                        }

                        self.syncController.start(type: .normal, libraries: .all, retryAttempt: 0)
                    }
                }

                it("shouldn't check for remote changes if some write action succeeded to reach zotero backend") {
                    let libraryId = self.userLibraryId

                    let key = "AAAAAAAA"
                    let filename = "doc.txt"
                    let data = "test string".data(using: .utf8)!
                    let file = Files.attachmentFile(in: libraryId, key: key, filename: filename, contentType: "text/plain")
                    try! FileStorageController().write(data, to: file, options: .atomicWrite)
                    let fileMd5 = md5(from: file.createUrl())!

                    let key2 = "BBBBBBBB"
                    let filename2 = "doc2.txt"
                    let file2 = Files.attachmentFile(in: libraryId, key: key2, filename: filename2, contentType: "text/plain")

                    let expected: [SyncController.Action] = [
                        .loadKeyPermissions,
                        .syncGroupVersions,
                        .createLibraryActions(.all, .automatic),
                        .createUploadActions(libraryId: libraryId, hadOtherWriteActions: false, canEditFiles: true),
                        .uploadAttachment(AttachmentUpload(libraryId: libraryId, key: key, filename: filename, contentType: "text/plain", md5: "md5hash1", mtime: 100, file: file, oldMd5: nil)),
                        .uploadAttachment(AttachmentUpload(libraryId: libraryId, key: key2, filename: filename2, contentType: "text/plain", md5: "md5hash2", mtime: 200, file: file2, oldMd5: nil))
                    ]

                    createStub(for: KeyRequest(), baseUrl: baseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys", withExtension: "json")!)
                    createStub(for: GroupVersionsRequest(userId: self.userId), baseUrl: baseUrl, headers: nil, statusCode: 200, jsonResponse: [:] as [String: Any])
                    createStub(
                        for: AuthorizeUploadRequest(libraryId: libraryId, userId: self.userId, key: key, filename: filename, filesize: UInt64(data.count), md5: fileMd5, mtime: 123, oldMd5: nil),
                        ignoreBody: true,
                        baseUrl: baseUrl,
                        jsonResponse: ["url": "https://www.upload-test.org/", "uploadKey": "key", "params": ["key": "key"]] as [String: Any]
                    )
                    createStub(
                        for: RegisterUploadRequest(libraryId: libraryId, userId: self.userId, key: key, uploadKey: "key", oldMd5: nil),
                        baseUrl: baseUrl,
                        headers: nil,
                        statusCode: 204,
                        jsonResponse: [:] as [String: Any]
                    )
                    stub(condition: { request -> Bool in
                        return request.url?.absoluteString == "https://www.upload-test.org/"
                    }, response: { _ -> HTTPStubsResponse in
                        return HTTPStubsResponse(jsonObject: [:] as [String: Any], statusCode: 201, headers: nil)
                    })

                    self.createNewSyncController()

                    try! self.realm.write {
                        let item = RItem()
                        item.key = key
                        item.rawType = "attachment"
                        item.customLibraryKey = .myLibrary
                        item.attachmentNeedsSync = true

                        let contentField = RItemField()
                        contentField.key = FieldKeys.Item.Attachment.contentType
                        contentField.value = "text/plain"
                        item.fields.append(contentField)

                        let filenameField = RItemField()
                        filenameField.key = FieldKeys.Item.Attachment.filename
                        filenameField.value = filename
                        item.fields.append(filenameField)

                        let linkModeField = RItemField()
                        linkModeField.key = FieldKeys.Item.Attachment.linkMode
                        linkModeField.value = LinkMode.importedFile.rawValue
                        item.fields.append(linkModeField)

                        let md5Field = RItemField()
                        md5Field.key = FieldKeys.Item.Attachment.md5
                        md5Field.value = "md5hash1"
                        item.fields.append(md5Field)

                        let mtimeField = RItemField()
                        mtimeField.key = FieldKeys.Item.Attachment.mtime
                        mtimeField.value = "100"
                        item.fields.append(mtimeField)

                        self.realm.add(item)

                        let item2 = RItem()
                        item2.key = key2
                        item2.rawType = "attachment"
                        item2.customLibraryKey = .myLibrary
                        item2.attachmentNeedsSync = true

                        let contentField2 = RItemField()
                        contentField2.key = FieldKeys.Item.Attachment.contentType
                        contentField2.value = "text/plain"
                        item2.fields.append(contentField2)

                        let filenameField2 = RItemField()
                        filenameField2.key = FieldKeys.Item.Attachment.filename
                        filenameField2.value = filename2
                        item2.fields.append(filenameField2)

                        let linkModeField2 = RItemField()
                        linkModeField2.key = FieldKeys.Item.Attachment.linkMode
                        linkModeField2.value = LinkMode.importedFile.rawValue
                        item2.fields.append(linkModeField2)

                        let md5Field2 = RItemField()
                        md5Field2.key = FieldKeys.Item.Attachment.md5
                        md5Field2.value = "md5hash2"
                        item2.fields.append(md5Field2)

                        let mtimeField2 = RItemField()
                        mtimeField2.key = FieldKeys.Item.Attachment.mtime
                        mtimeField2.value = "200"
                        item2.fields.append(mtimeField2)

                        self.realm.add(item2)
                    }

                    waitUntil(timeout: .seconds(10)) { doneAction in
                        self.syncController.reportFinish = { result in
                            switch result {
                            case .success(let data):
                                expect(data.0).to(equal(expected))

                            case .failure(let error):
                                fail("Failure: \(error)")
                            }

                            try? FileStorageController().remove(file)

                            doneAction()
                        }

                        self.syncController.start(type: .normal, libraries: .all, retryAttempt: 0)
                    }
                }
            }

            describe("WebDAV") {
                it("Creates zotero directory if missing and continues upload") {
                    let libraryId = self.userLibraryId
                    let key = "AAAAAAAA"
                    let filename = "test.txt"
                    let data = "test string".data(using: .utf8)!
                    let file = Files.attachmentFile(in: libraryId, key: key, filename: filename, contentType: "text/plain")
                    try! FileStorageController().write(data, to: file, options: .atomicWrite)
                    let md5 = md5(from: file.createUrl())!
                    let webDavUrl = URL(string: "http://test.com/zotero/")!
                    var didCreateParent = false

                    let expected: [SyncController.Action] = [
                        .loadKeyPermissions,
                        .syncGroupVersions,
                        .createLibraryActions(.all, .automatic),
                        .createUploadActions(libraryId: libraryId, hadOtherWriteActions: false, canEditFiles: true),
                        .uploadAttachment(AttachmentUpload(libraryId: libraryId, key: key, filename: filename, contentType: "text/plain", md5: md5, mtime: 1000, file: file, oldMd5: nil))
                    ]

                    createStub(for: KeyRequest(), baseUrl: baseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys", withExtension: "json")!)
                    createStub(for: GroupVersionsRequest(userId: self.userId), baseUrl: baseUrl, headers: nil, statusCode: 200, jsonResponse: [:] as [String: Any])
                    createStub(for: WebDavCheckRequest(url: webDavUrl), baseUrl: webDavUrl, headers: ["dav": "1"], statusCode: 200, jsonResponse: [:] as [String: Any])
                    stub(condition: WebDavPropfindRequest(url: webDavUrl).stubCondition(with: webDavUrl, ignoreBody: true), response: { _ -> HTTPStubsResponse in
                        return HTTPStubsResponse(jsonObject: [:] as [String: Any], statusCode: didCreateParent ? 207 : 404, headers: nil)
                    })
                    createStub(for: WebDavPropfindRequest(url: webDavUrl.deletingLastPathComponent()), baseUrl: webDavUrl, headers: nil, statusCode: 207, jsonResponse: [:] as [String: Any])
                    createStub(
                        for: WebDavCreateZoteroDirectoryRequest(url: webDavUrl),
                        baseUrl: webDavUrl,
                        headers: nil,
                        statusCode: 200,
                        jsonResponse: [:] as [String: Any],
                        responseAction: {
                            didCreateParent = true
                        }
                    )
                    createStub(for: WebDavNonexistentPropRequest(url: webDavUrl), baseUrl: webDavUrl, headers: nil, statusCode: 404, jsonResponse: [:] as [String: Any])
                    let writeRequest = WebDavTestWriteRequest(url: webDavUrl)
                    createStub(for: writeRequest, baseUrl: webDavUrl, headers: nil, statusCode: 200, jsonResponse: [:] as [String: Any])
                    createStub(for: WebDavDownloadRequest(endpoint: writeRequest.endpoint), baseUrl: webDavUrl, headers: nil, statusCode: 200, jsonResponse: [:] as [String: Any])
                    createStub(for: WebDavDeleteRequest(endpoint: writeRequest.endpoint), baseUrl: webDavUrl, headers: nil, statusCode: 200, jsonResponse: [:] as [String: Any])
                    createStub(for: WebDavDownloadRequest(url: webDavUrl.appendingPathComponent(key + ".prop")), baseUrl: webDavUrl, headers: nil, statusCode: 404, jsonResponse: [:] as [String: Any])
                    createStub(
                        for: WebDavWriteRequest(url: webDavUrl.appendingPathComponent(key + ".zip"), data: data),
                        ignoreBody: true,
                        baseUrl: webDavUrl,
                        headers: nil,
                        statusCode: 200,
                        jsonResponse: [:] as [String: Any]
                    )
                    createStub(
                        for: WebDavWriteRequest(url: webDavUrl.appendingPathComponent(key + ".prop"), data: data),
                        ignoreBody: true,
                        baseUrl: webDavUrl,
                        headers: nil,
                        statusCode: 200,
                        jsonResponse: [:] as [String: Any]
                    )
                    createStub(
                        for: UpdatesRequest(libraryId: libraryId, userId: self.userId, objectType: .item, params: [], version: nil),
                        ignoreBody: true,
                        baseUrl: baseUrl,
                        headers: nil,
                        statusCode: 200,
                        jsonResponse: [:] as [String: Any]
                    )

                    self.createNewSyncController()

                    self.webDavController.sessionStorage.isEnabled = true
                    self.webDavController.sessionStorage.scheme = .http
                    self.webDavController.sessionStorage.url = "test.com"
                    self.webDavController.sessionStorage.isVerified = false
                    self.webDavController.sessionStorage.username = "user"
                    self.webDavController.sessionStorage.password = "password"

                    try! self.realm.write {
                        let item = RItem()
                        item.key = key
                        item.rawType = "attachment"
                        item.customLibraryKey = .myLibrary
                        item.attachmentNeedsSync = true

                        let contentField = RItemField()
                        contentField.key = FieldKeys.Item.Attachment.contentType
                        contentField.value = "text/plain"
                        item.fields.append(contentField)

                        let md5Field = RItemField()
                        md5Field.key = FieldKeys.Item.Attachment.md5
                        md5Field.value = md5
                        item.fields.append(md5Field)

                        let mtimeField = RItemField()
                        mtimeField.key = FieldKeys.Item.Attachment.mtime
                        mtimeField.value = "1000"
                        item.fields.append(mtimeField)

                        let filenameField = RItemField()
                        filenameField.key = FieldKeys.Item.Attachment.filename
                        filenameField.value = filename
                        item.fields.append(filenameField)

                        let linkModeField = RItemField()
                        linkModeField.key = FieldKeys.Item.Attachment.linkMode
                        linkModeField.value = LinkMode.importedFile.rawValue
                        item.fields.append(linkModeField)

                        self.realm.add(item)
                    }

                    waitUntil(timeout: .seconds(10)) { doneAction in
                        self.syncController.reportFinish = { result in
                            switch result {
                            case .success(let data):
                                expect(data.0).to(equal(expected))
                                expect(didCreateParent).to(beTrue())

                            case .failure(let error):
                                fail("Failure: \(error)")
                            }

                            try? FileStorageController().remove(file)

                            doneAction()
                        }

                        self.syncController.start(type: .normal, libraries: .all, retryAttempt: 0)
                    }
                }
            }
        }
    }

    private func jsonParameters(from stream: InputStream) -> [[String: Any]] {
        let json = try? JSONSerialization.jsonObject(with: stream.data, options: .allowFragments)
        return (json as? [[String: Any]]) ?? []
    }

    private func itemJson(key: String, version: Int, type: String) -> [String: Any] {
        let itemUrl = Bundle(for: SyncControllerSpec.self).url(forResource: "test_item", withExtension: "json")!
        var itemJson = (try! JSONSerialization.jsonObject(with: (try! Data(contentsOf: itemUrl)), options: .allowFragments)) as! [String: Any]
        itemJson["key"] = key
        itemJson["version"] = version
        var itemData = itemJson["data"] as! [String: Any]
        itemData["itemType"] = type
        itemJson["data"] = itemData
        return itemJson
    }
}

extension InputStream {
    fileprivate var data: Data {
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        open()

        var amount = 0
        repeat {
            amount = read(&buffer, maxLength: buffer.count)
            if amount > 0 {
                result.append(buffer, count: amount)
            }
        } while amount > 0

        close()

        return result
    }
}

struct TestConflictCoordinator: ConflictReceiver & SyncRequestReceiver {
    let createZoteroDirectory: Bool

    func askToCreateZoteroDirectory(url: String, create: @escaping () -> Void, cancel: @escaping () -> Void) {
        if self.createZoteroDirectory {
            create()
        } else {
            cancel()
        }
    }

    func resolve(conflict: Conflict, completed: @escaping (ConflictResolution?) -> Void) {
        switch conflict {
        case .objectsRemovedRemotely(let libraryId, let collections, let items, let searches, let tags):
            completed(.remoteDeletionOfActiveObject(libraryId: libraryId, toDeleteCollections: collections, toRestoreCollections: [],
                                                    toDeleteItems: items, toRestoreItems: [], searches: searches, tags: tags))

        case .removedItemsHaveLocalChanges(let keys, let libraryId):
            completed(.remoteDeletionOfChangedItem(libraryId: libraryId, toDelete: keys.map({ $0.0 }), toRestore: []))

        case .groupRemoved(let id, _):
            completed(.deleteGroup(id))

        case .groupMetadataWriteDenied(let id, _):
            completed(.revertGroupChanges(.group(id)))

        case .groupFileWriteDenied(let id, _):
            completed(.revertGroupFiles(.group(id)))
        }
    }

    func askForPermission(message: String, completed: @escaping (DebugPermissionResponse) -> Void) {
        completed(.allowed)
    }
}
