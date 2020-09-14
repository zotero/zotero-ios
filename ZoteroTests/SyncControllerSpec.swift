//
//  SyncControllerSpec.swift
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
import RxAlamofire
import RxSwift
import Quick

class SyncControllerSpec: QuickSpec {
    private static let userId = 100
    private static let apiClient = ZoteroApiClient(baseUrl: ApiConstants.baseUrlString, configuration: URLSessionConfiguration.default)
    private static let fileStorage = FileStorageController()
    private static let schemaController = SchemaController()
    private static let dateParser = DateParser()
    private static let userLibraryId: LibraryIdentifier = .custom(.myLibrary)

    private static var realmConfig: Realm.Configuration!
    private static var realm: Realm!
    private static var syncController: SyncController!

    private static func createNewSyncController() {
        // Create new realm with empty data
        let memoryId = UUID().uuidString
        let config = Realm.Configuration(inMemoryIdentifier: memoryId)
        let realm = try! Realm(configuration: config)
        // Create "My Library" in new realm
        try! realm.write {
            let myLibrary = RCustomLibrary()
            myLibrary.rawType = RCustomLibraryType.myLibrary.rawValue
            realm.add(myLibrary)
        }
        // Create DB storage with the same config
        let dbStorage = RealmDbStorage(config: config)
        // Create background uploader with storage
        let backgroundUploader = BackgroundUploader(uploadProcessor: BackgroundUploadProcessor(apiClient: apiClient,
                                                                                               dbStorage: dbStorage,
                                                                                               fileStorage: fileStorage), schemaVersion: 3)

        // Store config so that realms can be created from other threads as well (used when checking db state after sync finished)
        SyncControllerSpec.realmConfig = config
        // Store realm so that it's not deallocated and its data removed
        SyncControllerSpec.realm = realm
        SyncControllerSpec.syncController = SyncController(userId: userId,
                                                           apiClient: apiClient,
                                                           dbStorage: dbStorage,
                                                           fileStorage: fileStorage,
                                                           schemaController: schemaController,
                                                           dateParser: dateParser,
                                                           backgroundUploader: backgroundUploader,
                                                           syncDelayIntervals: [0, 1, 2, 3],
                                                           conflictDelays: [0, 1, 2, 3])
    }

    override func spec() {

        beforeEach {
            HTTPStubs.removeAllStubs()
            Defaults.shared.userId = SyncControllerSpec.userId

            SyncControllerSpec.realmConfig = nil
            SyncControllerSpec.realm = nil
            SyncControllerSpec.syncController = nil
        }

        describe("Syncing") {
            let baseUrl = URL(string: ApiConstants.baseUrlString)!

            describe("Download") {
                it("should download items into a new library") {
                    let header = ["last-modified-version" : "3"]
                    let libraryId = SyncControllerSpec.userLibraryId
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
                                                        "library": ["id": 0, "type": "user", "name": "A"],
                                                        "data": ["name": "A"]]]
                        case .search:
                            objectResponses[object] = [["key": "AAAAAAAA",
                                                        "version": 2,
                                                        "library": ["id": 0, "type": "user", "name": "A"],
                                                        "data": ["name": "A",
                                                                 "conditions": [["condition": "itemType",
                                                                                 "operator": "is",
                                                                                 "value": "thesis"]]]]]
                        case .item:
                            objectResponses[object] = [["key": "AAAAAAAA",
                                                        "version": 3,
                                                        "library": ["id": 0, "type": "user", "name": "A"],
                                                        "data": ["title": "A", "itemType": "thesis",
                                                                 "tags": [["tag": "A"]]]]]
                        case .trash:
                            objectResponses[object] = [["key": "BBBBBBBB",
                                                        "version": 4,
                                                        "library": ["id": 0, "type": "user", "name": "A"],
                                                        "data": ["note": "<p>This is a note</p>",
                                                                 "parentItem": "AAAAAAAA",
                                                                 "itemType": "note",
                                                                 "deleted": 1]]]
                        }
                    }

                    createStub(for: GroupVersionsRequest(userId: SyncControllerSpec.userId),
                               baseUrl: baseUrl, headers: header, jsonResponse: [:])
                    objects.forEach { object in
                        createStub(for: VersionsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId,
                                                                     objectType: object, version: 0),
                                        baseUrl: baseUrl, headers: header,
                                        jsonResponse: (versionResponses[object] ?? [:]))
                    }
                    objects.forEach { object in
                        createStub(for: ObjectsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, objectType: object, keys: (objectKeys[object] ?? "")),
                                        baseUrl: baseUrl, headers: header,
                                        jsonResponse: (objectResponses[object] ?? [:]))
                    }
                    createStub(for: KeyRequest(), baseUrl: baseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys", withExtension: "json")!)
                    createStub(for: SettingsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    jsonResponse: ["tagColors" : ["value": [["name": "A", "color": "#CC66CC"]], "version": 2]])
                    createStub(for: DeletionsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    jsonResponse: ["collections": [], "searches": [], "items": [], "tags": []])

                    SyncControllerSpec.createNewSyncController()

                    waitUntil(timeout: 10) { doneAction in
                        SyncControllerSpec.syncController.reportFinish = { _ in
                            let realm = try! Realm(configuration: SyncControllerSpec.realmConfig)
                            realm.refresh()

                            let library = realm.objects(RCustomLibrary.self).first
                            expect(libraryId).toNot(beNil())
                            expect(library?.type).to(equal(.myLibrary))

                            expect(library?.collections.count).to(equal(1))
                            expect(library?.items.count).to(equal(2))
//                            expect(library?.searches.count).to(equal(1))
                            expect(library?.tags.count).to(equal(1))
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
                            expect(collection?.customLibrary?.type).to(equal(.myLibrary))
                            expect(collection?.parent).to(beNil())
                            expect(collection?.children.count).to(equal(0))

                            let item = realm.objects(RItem.self).filter("key = %@", "AAAAAAAA").first
                            expect(item).toNot(beNil())
                            expect(item?.baseTitle).to(equal("A"))
                            expect(item?.version).to(equal(3))
                            expect(item?.trash).to(beFalse())
                            expect(item?.syncState).to(equal(.synced))
                            expect(item?.customLibrary?.type).to(equal(.myLibrary))
                            expect(item?.collections.count).to(equal(0))
                            expect(item?.fields.count).to(equal(1))
                            expect(item?.fields.first?.key).to(equal("title"))
                            expect(item?.parent).to(beNil())
                            expect(item?.children.count).to(equal(1))
                            expect(item?.tags.count).to(equal(1))
                            expect(item?.tags.first?.name).to(equal("A"))

                            let item2 = realm.objects(RItem.self).filter("key = %@", "BBBBBBBB").first
                            expect(item2).toNot(beNil())
                            expect(item2?.baseTitle).to(equal("This is a note"))
                            expect(item2?.version).to(equal(4))
                            expect(item2?.trash).to(beTrue())
                            expect(item2?.syncState).to(equal(.synced))
                            expect(item2?.customLibrary?.type).to(equal(.myLibrary))
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
                            expect(tag?.items.count).to(equal(1))

                            doneAction()
                        }

                        SyncControllerSpec.syncController?.start(type: .normal, libraries: .all)
                    }
                }

                it("should download items into a new read-only group") {
                    let header = ["last-modified-version" : "3"]
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
                                                        "library": ["id": groupId, "type": "group", "name": "A"],
                                                        "data": ["name": "A"]]]
                        case .search:
                            objectResponses[object] = [["key": "AAAAAAAA",
                                                        "version": 2,
                                                        "library": ["id": groupId, "type": "group", "name": "A"],
                                                        "data": ["name": "A",
                                                                 "conditions": [["condition": "itemType",
                                                                                 "operator": "is",
                                                                                 "value": "thesis"]]]]]
                        case .item:
                            objectResponses[object] = [["key": "AAAAAAAA",
                                                        "version": 3,
                                                        "library": ["id": groupId, "type": "group", "name": "A"],
                                                        "data": ["title": "A", "itemType":
                                                                 "thesis", "tags": [["tag": "A"]]]]]
                        case .trash:
                            objectResponses[object] = [["key": "BBBBBBBB",
                                                        "version": 4,
                                                        "library": ["id": groupId, "type": "group", "name": "A"],
                                                        "data": ["note": "<p>This is a note</p>",
                                                                 "parentItem": "AAAAAAAA",
                                                                 "itemType": "note",
                                                                 "deleted": 1]]]
                        }
                    }

                    let groupVersionsResponse: [String: Any] = [groupId.description: 2]
                    let groupObjectResponse: [String: Any] = ["id": groupId,
                                                              "version": 2,
                                                              "data": ["name": "Group",
                                                                       "owner": SyncControllerSpec.userId,
                                                                       "type": "Private",
                                                                       "description": "",
                                                                       "libraryEditing": "members",
                                                                       "libraryReading": "members",
                                                                       "fileEditing": "members"]]

                    let myLibrary = SyncControllerSpec.userLibraryId

                    createStub(for: GroupVersionsRequest(userId: SyncControllerSpec.userId), baseUrl: baseUrl, headers: header,
                               jsonResponse: groupVersionsResponse)
                    objects.forEach { object in
                        createStub(for: VersionsRequest(libraryId: myLibrary, userId: SyncControllerSpec.userId, objectType: object, version: 0),
                                        baseUrl: baseUrl, headers: header, jsonResponse: [:])
                    }
                    createStub(for: GroupRequest(identifier: groupId), baseUrl: baseUrl, headers: header, jsonResponse: groupObjectResponse)
                    for object in objects {
                        createStub(for: VersionsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, objectType: object, version: 0),
                                        baseUrl: baseUrl, headers: header,
                                        jsonResponse: (versionResponses[object] ?? [:]))
                    }
                    for object in objects {
                        createStub(for: ObjectsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, objectType: object, keys: (objectKeys[object] ?? "")),
                                        baseUrl: baseUrl, headers: header,
                                        jsonResponse: (objectResponses[object] ?? [:]))
                    }
                    createStub(for: KeyRequest(), baseUrl: baseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys", withExtension: "json")!)
                    createStub(for: SettingsRequest(libraryId: myLibrary, userId: SyncControllerSpec.userId, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    jsonResponse: ["tagColors" : ["value": [], "version": 2]])
                    createStub(for: SettingsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    jsonResponse: ["tagColors" : ["value": [["name": "A", "color": "#CC66CC"]], "version": 2]])
                    createStub(for: DeletionsRequest(libraryId: myLibrary, userId: SyncControllerSpec.userId, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    jsonResponse: ["collections": [], "searches": [], "items": [], "tags": []])
                    createStub(for: DeletionsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    jsonResponse: ["collections": [], "searches": [], "items": [], "tags": []])

                    SyncControllerSpec.createNewSyncController()

                    waitUntil(timeout: 10) { doneAction in
                        SyncControllerSpec.syncController.reportFinish = { _ in
                            let realm = try! Realm(configuration: SyncControllerSpec.realmConfig)
                            realm.refresh()

                            let myLibrary = realm.object(ofType: RCustomLibrary.self,
                                                         forPrimaryKey: RCustomLibraryType.myLibrary.rawValue)
                            expect(myLibrary).toNot(beNil())
                            expect(myLibrary?.collections.count).to(equal(0))
                            expect(myLibrary?.items.count).to(equal(0))
                            expect(myLibrary?.searches.count).to(equal(0))
                            expect(myLibrary?.tags.count).to(equal(0))

                            let group = realm.object(ofType: RGroup.self, forPrimaryKey: groupId)
                            expect(group).toNot(beNil())
                            expect(group?.collections.count).to(equal(1))
                            expect(group?.items.count).to(equal(2))
//                            expect(group?.searches.count).to(equal(1))
                            expect(group?.tags.count).to(equal(1))

                            let versions = group?.versions
                            expect(versions).toNot(beNil())
                            expect(versions?.collections).to(equal(3))
                            expect(versions?.deletions).to(equal(3))
                            expect(versions?.items).to(equal(3))
//                            expect(versions?.searches).to(equal(3))
                            expect(versions?.settings).to(equal(3))
                            expect(versions?.trash).to(equal(3))

                            let collection = realm.objects(RCollection.self)
                                .filter(.key("AAAAAAAA", in: .group(groupId))).first
                            expect(collection).toNot(beNil())
                            let item = realm.objects(RItem.self)
                                .filter(.key("AAAAAAAA", in: .group(groupId))).first
                            expect(item).toNot(beNil())
                            let item2 = realm.objects(RItem.self)
                                .filter(.key("BBBBBBBB", in: .group(groupId))).first
                            expect(item2).toNot(beNil())
//                            let search = realm.objects(RSearch.self)
//                                .filter(.key("AAAAAAAA", in: .group(groupId))).first
//                            expect(search).toNot(beNil())
                            let tag = realm.objects(RTag.self)
                                .filter(.name("A", in: .group(groupId))).first
                            expect(tag).toNot(beNil())

                            doneAction()
                        }

                        SyncControllerSpec.syncController.start(type: .normal, libraries: .all)
                    }
                }

                it("should apply remote deletions") {
                    let header = ["last-modified-version" : "3"]
                    let libraryId = SyncControllerSpec.userLibraryId
                    let itemToDelete = "CCCCCCCC"
                    let objects = SyncObject.allCases

                    SyncControllerSpec.createNewSyncController()

                    let realm = SyncControllerSpec.realm!
                    try! realm.write {
                        let myLibrary = SyncControllerSpec.realm.objects(RCustomLibrary.self).first
                        let item = RItem()
                        item.key = itemToDelete
                        item.baseTitle = "Delete me"
                        item.customLibrary = myLibrary
                        realm.add(item)
                    }

                    let toBeDeletedItem = realm.objects(RItem.self).filter(.key(itemToDelete, in: .custom(.myLibrary))).first
                    expect(toBeDeletedItem).toNot(beNil())

                    createStub(for: GroupVersionsRequest(userId: SyncControllerSpec.userId), baseUrl: baseUrl, headers: header,
                               jsonResponse: [:])
                    objects.forEach { object in
                        createStub(for: VersionsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId,
                                                                     objectType: object, version: 0),
                                        baseUrl: baseUrl, headers: header,
                                        jsonResponse: [:])
                    }
                    createStub(for: KeyRequest(), baseUrl: baseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys", withExtension: "json")!)
                    createStub(for: SettingsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    jsonResponse: ["tagColors" : ["value": [], "version": 2]])
                    createStub(for: DeletionsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    jsonResponse: ["collections": [], "searches": [], "items": [itemToDelete], "tags": []])

                    waitUntil(timeout: 10) { doneAction in
                        SyncControllerSpec.syncController.reportFinish = { _ in
                            let realm = try! Realm(configuration: SyncControllerSpec.realmConfig)
                            realm.refresh()

                            let deletedItem = realm.objects(RItem.self).filter(.key(itemToDelete, in: .custom(.myLibrary))).first
                            expect(deletedItem).to(beNil())

                            doneAction()
                        }

                        SyncControllerSpec.syncController.start(type: .normal, libraries: .all)
                    }
                }

                // TODO: Enable when proper CR is implemented
//                it("should ignore remote deletions if local object changed") {
//                    let header = ["last-modified-version" : "3"]
//                    let libraryId = SyncControllerSpec.userLibraryId
//                    let itemToDelete = "DDDDDDDD"
//                    let objects = SyncObject.allCases
//
//                    let realm = SyncControllerSpec.realm
//                    try! realm.write {
//                        let myLibrary = SyncControllerSpec.realm.objects(RCustomLibrary.self).first
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
//                    let request = UpdatesRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, objectType: .item, params: [], version: 0)
//                    // We don't care about specific post params here, we just want to track all update requests
//                    let condition = request.stubCondition(with: baseUrl, ignorePostParams: true)
//                    stub(condition: condition, response: { _ -> HTTPStubsResponse in
//                        let code = statusCode
//                        statusCode = 200
//                        return HTTPStubsResponse(jsonObject: [:], statusCode: code, headers: header)
//                    })
//                    objects.forEach { object in
//                        let version: Int? = object == .group ? nil : 0
//                        createStub(for: VersionsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId,
//                                                                     objectType: object, version: version),
//                                        baseUrl: baseUrl, headers: header,
//                                        response: [:])
//                    }
//                    createStub(for: KeyRequest(), baseUrl: baseUrl, response: ["access": ["":""]])
//                    createStub(for: SettingsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, version: 0),
//                                    baseUrl: baseUrl, headers: header,
//                                    response: ["tagColors" : ["value": [], "version": 2]])
//                    createStub(for: DeletionsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, version: 0),
//                                    baseUrl: baseUrl, headers: header,
//                                    response: ["collections": [], "searches": [], "items": [itemToDelete], "tags": []])
//
//                    self.controller = SyncController(userId: SyncControllerSpec.userId,
//                                                     handler: SyncControllerSpec.syncHandler,
//                                                     conflictDelays: SyncControllerSpec.delays)
//
//                    waitUntil(timeout: 10) { doneAction in
//                        self.controller?.reportFinish = { result in
//                            let realm = try! Realm(configuration: SyncControllerSpec.realmConfig)
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
                    let header = ["last-modified-version" : "3"]
                    let libraryId = SyncControllerSpec.userLibraryId
                    let objects = SyncObject.allCases
                    let itemKey = "AAAAAAAA"
                    let collectionKey = "CCCCCCCC"
                    let itemResponse = [["key": itemKey,
                                         "version": 3,
                                         "library": ["id": 0, "type": "user", "name": "A"],
                                         "data": ["title": "A", "itemType": "thesis", "collections": [collectionKey]]]]

                    SyncControllerSpec.createNewSyncController()

                    let realm = SyncControllerSpec.realm!
                    let collection = realm.objects(RItem.self).filter("key = %@", collectionKey).first
                    expect(collection).to(beNil())

                    createStub(for: GroupVersionsRequest(userId: SyncControllerSpec.userId), baseUrl: baseUrl, headers: header,
                               jsonResponse: [:])
                    objects.forEach { object in
                        if object == .item {
                            createStub(for: VersionsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, objectType: object, version: 0),
                                            baseUrl: baseUrl, headers: header,
                                            jsonResponse: [itemKey: 3])
                        } else {
                            createStub(for: VersionsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId,
                                                                         objectType: object, version: 0),
                                            baseUrl: baseUrl, headers: header,
                                            jsonResponse: [:])
                        }
                    }
                    createStub(for: KeyRequest(), baseUrl: baseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys", withExtension: "json")!)
                    createStub(for: ObjectsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, objectType: .item, keys: itemKey),
                                    baseUrl: baseUrl, headers: header, jsonResponse: itemResponse)
                    createStub(for: SettingsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    jsonResponse: ["tagColors" : ["value": [], "version": 2]])
                    createStub(for: DeletionsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    jsonResponse: ["collections": [], "searches": [], "items": [], "tags": []])

                    waitUntil(timeout: 10) { doneAction in
                        SyncControllerSpec.syncController.reportFinish = { _ in
                            let realm = try! Realm(configuration: SyncControllerSpec.realmConfig)
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

                        SyncControllerSpec.syncController.start(type: .normal, libraries: .all)
                    }
                }

                it("should include unsynced objects in sync queue") {
                    let header = ["last-modified-version" : "3"]
                    let libraryId = SyncControllerSpec.userLibraryId
                    let objects = SyncObject.allCases
                    let unsyncedItemKey = "AAAAAAAA"
                    let responseItemKey = "BBBBBBBB"
                    let itemResponse = [["key": responseItemKey,
                                         "version": 3,
                                         "library": ["id": 0, "type": "user", "name": "A"],
                                         "data": ["title": "A", "itemType": "thesis"]],
                                        ["key": unsyncedItemKey,
                                         "version": 3,
                                         "library": ["id": 0, "type": "user", "name": "A"],
                                         "data": ["title": "B", "itemType": "thesis"]]]

                    SyncControllerSpec.createNewSyncController()

                    let realm = SyncControllerSpec.realm!
                    try! realm.write {
                        let library = realm.object(ofType: RCustomLibrary.self,
                                                   forPrimaryKey: RCustomLibraryType.myLibrary.rawValue)
                        let item = RItem()
                        item.key = unsyncedItemKey
                        item.syncState = .dirty
                        item.customLibrary = library
                        realm.add(item)
                    }

                    let unsynced = realm.objects(RItem.self).filter(.key(unsyncedItemKey, in: .custom(.myLibrary))).first
                    expect(unsynced).toNot(beNil())
                    expect(unsynced?.syncState).to(equal(.dirty))

                    createStub(for: GroupVersionsRequest(userId: SyncControllerSpec.userId), baseUrl: baseUrl, headers: header,
                               jsonResponse: [:])
                    objects.forEach { object in
                        if object == .item {
                            createStub(for: VersionsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, objectType: object, version: 0),
                                            baseUrl: baseUrl, headers: header,
                                            jsonResponse: [responseItemKey: 3])
                        } else {
                            createStub(for: VersionsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId,
                                                                         objectType: object, version: 0),
                                            baseUrl: baseUrl, headers: header,
                                            jsonResponse: [:])
                        }
                    }
                    createStub(for: KeyRequest(), baseUrl: baseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys", withExtension: "json")!)
                    createStub(for: ObjectsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, objectType: .item,
                                                        keys: "\(unsyncedItemKey),\(responseItemKey)"),
                                    baseUrl: baseUrl, headers: header, jsonResponse: itemResponse)
                    createStub(for: ObjectsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, objectType: .item,
                                                        keys: "\(responseItemKey),\(unsyncedItemKey)"),
                                    baseUrl: baseUrl, headers: header, jsonResponse: itemResponse)
                    createStub(for: SettingsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    jsonResponse: ["tagColors" : ["value": [], "version": 2]])
                    createStub(for: DeletionsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    jsonResponse: ["collections": [], "searches": [], "items": [], "tags": []])

                    waitUntil(timeout: 10) { doneAction in
                        SyncControllerSpec.syncController.reportFinish = { result in
                            let realm = try! Realm(configuration: SyncControllerSpec.realmConfig)
                            realm.refresh()

                            switch result {
                            case .success(let data):
                                let actions = data.0
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

                        SyncControllerSpec.syncController.start(type: .normal, libraries: .all)
                    }
                }

                it("should mark object as needsSync if not parsed correctly and syncRetries should be increased") {
                    let header = ["last-modified-version" : "3"]
                    let libraryId = SyncControllerSpec.userLibraryId
                    let objects = SyncObject.allCases
                    let correctKey = "AAAAAAAA"
                    let incorrectKey = "BBBBBBBB"
                    let itemResponse = [["key": correctKey,
                                         "version": 3,
                                         "library": ["id": 0, "type": "user", "name": "A"],
                                         "data": ["title": "A", "itemType": "thesis"]],
                                        ["key": incorrectKey,
                                         "version": 3,
                                         "data": ["title": "A", "itemType": "thesis"]]]

                    createStub(for: GroupVersionsRequest(userId: SyncControllerSpec.userId),
                               baseUrl: baseUrl, headers: header,
                               jsonResponse: [:])
                    objects.forEach { object in
                        if object == .item {
                            createStub(for: VersionsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, objectType: object, version: 0),
                                            baseUrl: baseUrl, headers: header,
                                            jsonResponse: [correctKey: 3, incorrectKey: 3])
                        } else {
                            createStub(for: VersionsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId,
                                                                         objectType: object, version: 0),
                                            baseUrl: baseUrl, headers: header,
                                            jsonResponse: [:])
                        }
                    }
                    createStub(for: KeyRequest(), baseUrl: baseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys", withExtension: "json")!)
                    createStub(for: ObjectsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, objectType: .item,
                                                        keys: "\(correctKey),\(incorrectKey)"),
                                    baseUrl: baseUrl, headers: header, jsonResponse: itemResponse)
                    createStub(for: ObjectsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, objectType: .item,
                                                        keys: "\(incorrectKey),\(correctKey)"),
                                    baseUrl: baseUrl, headers: header, jsonResponse: itemResponse)
                    createStub(for: SettingsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    jsonResponse: ["tagColors" : ["value": [], "version": 2]])
                    createStub(for: DeletionsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    jsonResponse: ["collections": [], "searches": [], "items": [], "tags": []])

                    SyncControllerSpec.createNewSyncController()

                    waitUntil(timeout: 10) { doneAction in
                        SyncControllerSpec.syncController.reportFinish = { result in
                            let realm = try! Realm(configuration: SyncControllerSpec.realmConfig)
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

                        SyncControllerSpec.syncController.start(type: .normal, libraries: .all)
                    }
                }

                it("should ignore errors when saving downloaded objects") {
                    let header = ["last-modified-version" : "2"]
                    let libraryId = SyncControllerSpec.userLibraryId
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
                        case .trash: break
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
                                                        "library": ["id": 0, "type": "user", "name": "A"],
                                                        "data": ["name": "A"]],
                                                       // Missing parent - should be synced, parent queued
                                                       ["key": "BBBBBBBB",
                                                        "version": 1,
                                                        "library": ["id": 0, "type": "user", "name": "A"],
                                                        "data": ["name": "B",
                                                                 "parentCollection": "ZZZZZZZZ"]],
                                                       // Unknown field - should be rejected
                                                       ["key": "CCCCCCCC",
                                                        "version": 1,
                                                        "library": ["id": 0, "type": "user", "name": "A"],
                                                        "data": ["name": "C", "unknownField": 5]]]
                        case .search:
                                                       // Unknown condition - should be queued
                            objectResponses[object] = [["key": "GGGGGGGG",
                                                        "version": 2,
                                                        "library": ["id": 0, "type": "user", "name": "A"],
                                                        "data": ["name": "G",
                                                                 "conditions": [["condition": "unknownCondition",
                                                                                 "operator": "is",
                                                                                 "value": "thesis"]]]],
                                                       // Unknown operator - should be queued
                                                       ["key": "HHHHHHHH",
                                                        "version": 2,
                                                        "library": ["id": 0, "type": "user", "name": "A"],
                                                        "data": ["name": "H",
                                                                 "conditions": [["condition": "itemType",
                                                                                 "operator": "unknownOperator",
                                                                                 "value": "thesis"]]]]]
                        case .item:
                                                       // Unknown field - should be rejected
                            objectResponses[object] = [["key": "DDDDDDDD",
                                                        "version": 3,
                                                        "library": ["id": 0, "type": "user", "name": "A"],
                                                        "data": ["title": "D", "itemType":
                                                                 "thesis", "tags": [], "unknownField": "B"]],
                                                       // Unknown item type - should be queued
                                                       ["key": "EEEEEEEE",
                                                        "version": 3,
                                                        "library": ["id": 0, "type": "user", "name": "A"],
                                                        "data": ["title": "E", "itemType": "unknownType", "tags": []]],
                                                       // Parent didn't sync, but item is fine - should be synced
                                                       ["key": "FFFFFFFF",
                                                        "version": 3,
                                                        "library": ["id": 0, "type": "user", "name": "A"],
                                                        "data": ["note": "This is a note", "itemType": "note",
                                                                 "tags": [], "parentItem": "EEEEEEEE"]]]
                        case .trash: break
                        }
                    }

                    createStub(for: GroupVersionsRequest(userId: SyncControllerSpec.userId), baseUrl: baseUrl, headers: header,
                               jsonResponse: [:])
                    objects.forEach { object in
                        createStub(for: VersionsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId,
                                                                     objectType: object, version: 0),
                                        baseUrl: baseUrl, headers: header,
                                        jsonResponse: (versionResponses[object] ?? [:]))
                    }
                    objects.forEach { object in
                        createStub(for: ObjectsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, objectType: object,
                                                       keys: (objectKeys[object] ?? "")),
                                        baseUrl: baseUrl, headers: header,
                                        jsonResponse: (objectResponses[object] ?? [:]))
                    }
                    createStub(for: KeyRequest(), baseUrl: baseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys",
                                                                                                         withExtension: "json")!)
                    createStub(for: SettingsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    jsonResponse: ["tagColors" : ["value": [["name": "A", "color": "#CC66CC"]], "version": 2]])
                    createStub(for: DeletionsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    jsonResponse: ["collections": [], "searches": [], "items": [], "tags": []])

                    SyncControllerSpec.createNewSyncController()

                    waitUntil(timeout: 10) { doneAction in
                        SyncControllerSpec.syncController.reportFinish = { _ in
                            let realm = try! Realm(configuration: SyncControllerSpec.realmConfig)
                            realm.refresh()

                            let library = realm.objects(RCustomLibrary.self).first
                            expect(libraryId).toNot(beNil())
                            expect(library?.type).to(equal(.myLibrary))

                            expect(library?.collections.count).to(equal(3))
                            expect(library?.items.count).to(equal(2))
//                            expect(library?.searches.count).to(equal(3))
                            expect(realm.objects(RCollection.self).count).to(equal(3))
//                            expect(realm.objects(RSearch.self).count).to(equal(3))
                            expect(realm.objects(RItem.self).count).to(equal(2))

                            let collection = realm.objects(RCollection.self).filter("key = %@", "AAAAAAAA").first
                            expect(collection).toNot(beNil())
                            expect(collection?.name).to(equal("A"))
                            expect(collection?.syncState).to(equal(.synced))
                            expect(collection?.version).to(equal(1))
                            expect(collection?.customLibrary?.type).to(equal(.myLibrary))
                            expect(collection?.parent).to(beNil())
                            expect(collection?.children.count).to(equal(0))

                            let collection2 = realm.objects(RCollection.self).filter("key = %@", "BBBBBBBB").first
                            expect(collection2).toNot(beNil())
                            expect(collection2?.name).to(equal("B"))
                            expect(collection2?.syncState).to(equal(.synced))
                            expect(collection2?.version).to(equal(1))
                            expect(collection2?.customLibrary?.type).to(equal(.myLibrary))
                            expect(collection2?.parent?.key).to(equal("ZZZZZZZZ"))
                            expect(collection2?.children.count).to(equal(0))

                            let collection3 = realm.objects(RCollection.self).filter("key = %@", "CCCCCCCC").first
                            expect(collection3).to(beNil())

                            let collection4 = realm.objects(RCollection.self).filter("key = %@", "ZZZZZZZZ").first
                            expect(collection4).toNot(beNil())
                            expect(collection4?.syncState).to(equal(.dirty))
                            expect(collection4?.customLibrary?.type).to(equal(.myLibrary))
                            expect(collection4?.parent).to(beNil())
                            expect(collection4?.children.count).to(equal(1))

                            let item = realm.objects(RItem.self).filter("key = %@", "DDDDDDDD").first
                            expect(item).to(beNil())

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

                        SyncControllerSpec.syncController.start(type: .normal, libraries: .all)
                    }
                }

                it("should add items that exist remotely in a locally deleted," +
                   " remotely modified collection back to collection") {
                    let header = ["last-modified-version" : "1"]
                    let libraryId = SyncControllerSpec.userLibraryId
                    let objects = SyncObject.allCases
                    let collectionKey = "AAAAAAAA"

                    SyncControllerSpec.createNewSyncController()

                    let realm = SyncControllerSpec.realm!
                    try! realm.write {
                        let library = realm.object(ofType: RCustomLibrary.self,
                                                   forPrimaryKey: RCustomLibraryType.myLibrary.rawValue)

                        let versions = RVersions()
                        realm.add(versions)
                        library?.versions = versions

                        let collection = RCollection()
                        collection.key = collectionKey
                        collection.name = "Locally deleted collection"
                        collection.version = 0
                        collection.deleted = true
                        collection.customLibrary = library
                        realm.add(collection)

                        let item1 = RItem()
                        item1.key = "BBBBBBBB"
                        item1.baseTitle = "B"
                        item1.customLibrary = library
                        item1.collections.append(collection)
                        realm.add(item1)

                        let item2 = RItem()
                        item2.key = "CCCCCCCC"
                        item2.baseTitle = "C"
                        item2.customLibrary = library
                        item2.collections.append(collection)
                        realm.add(item2)
                    }

                    let versionResponses: [SyncObject: Any] = [.collection: [collectionKey: 1]]
                    let objectKeys: [SyncObject: String] = [.collection: collectionKey]
                    let collectionData: [[String: Any]] = [["key": collectionKey,
                                                            "version": 1,
                                                            "library": ["id": 0, "type": "user", "name": "A"],
                                                            "data": ["name": "A"]]]
                    let objectResponses: [SyncObject: Any] = [.collection: collectionData]

                    createStub(for: SubmitDeletionsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, objectType: .collection,
                                                                keys: [collectionKey], version: 0),
                                    baseUrl: baseUrl, headers: header, statusCode: 412, jsonResponse: [:])
                    createStub(for: GroupVersionsRequest(userId: SyncControllerSpec.userId), baseUrl: baseUrl, headers: header,
                               jsonResponse: [:])
                    objects.forEach { object in
                        createStub(for: VersionsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId,
                                                                     objectType: object, version: 0),
                                        baseUrl: baseUrl, headers: header,
                                        jsonResponse: (versionResponses[object] ?? [:]))
                    }
                    objects.forEach { object in
                        createStub(for: ObjectsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, objectType: object,
                                                            keys: (objectKeys[object] ?? "")),
                                        baseUrl: baseUrl, headers: header,
                                        jsonResponse: (objectResponses[object] ?? [:]))
                    }
                    createStub(for: KeyRequest(), baseUrl: baseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys", withExtension: "json")!)
                    createStub(for: SettingsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    jsonResponse: ["tagColors" : ["value": [["name": "A", "color": "#CC66CC"]], "version": 1]])
                    createStub(for: DeletionsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    jsonResponse: ["collections": [], "searches": [], "items": [], "tags": []])

                    waitUntil(timeout: 10) { doneAction in
                        SyncControllerSpec.syncController.reportFinish = { _ in
                            let realm = try! Realm(configuration: SyncControllerSpec.realmConfig)
                            realm.refresh()

                            let library = realm.objects(RCustomLibrary.self).first
                            expect(libraryId).toNot(beNil())
                            expect(library?.type).to(equal(.myLibrary))

                            expect(library?.collections.count).to(equal(1))
                            expect(library?.items.count).to(equal(2))
                            expect(realm.objects(RCollection.self).count).to(equal(1))
                            expect(realm.objects(RItem.self).count).to(equal(2))

                            let collection = realm.objects(RCollection.self).filter("key = %@", collectionKey).first
                            expect(collection).toNot(beNil())
                            expect(collection?.syncState).to(equal(.synced))
                            expect(collection?.version).to(equal(1))
                            expect(collection?.deleted).to(beFalse())
                            expect(collection?.customLibrary?.type).to(equal(.myLibrary))
                            expect(collection?.parent).to(beNil())
                            expect(collection?.items.count).to(equal(2))

                            doneAction()
                        }

                        SyncControllerSpec.syncController.start(type: .normal, libraries: .all)
                    }
                }

                it("should add locally deleted items that exist remotely in a locally deleted, remotely modified" +
                   " collection to sync queue and remove from delete log") {
                    let header = ["last-modified-version" : "1"]
                    let libraryId = SyncControllerSpec.userLibraryId
                    let objects = SyncObject.allCases
                    let collectionKey = "AAAAAAAA"
                    let deletedItemKey = "CCCCCCCC"

                    SyncControllerSpec.createNewSyncController()

                    let realm = SyncControllerSpec.realm!
                    try! realm.write {
                        let library = realm.object(ofType: RCustomLibrary.self,
                                                   forPrimaryKey: RCustomLibraryType.myLibrary.rawValue)

                        let versions = RVersions()
                        versions.collections = 1
                        versions.items = 1
                        versions.trash = 1
                        versions.searches = 1
                        versions.settings = 1
                        versions.deletions = 1
                        realm.add(versions)
                        library?.versions = versions

                        let collection = RCollection()
                        collection.key = collectionKey
                        collection.name = "Locally deleted collection"
                        collection.version = 1
                        collection.deleted = true
                        collection.customLibrary = library
                        realm.add(collection)

                        let item1 = RItem()
                        item1.key = "BBBBBBBB"
                        item1.baseTitle = "B"
                        item1.customLibrary = library
                        item1.collections.append(collection)
                        realm.add(item1)

                        let item2 = RItem()
                        item2.key = deletedItemKey
                        item2.baseTitle = "C"
                        item2.deleted = true
                        item2.customLibrary = library
                        item2.collections.append(collection)
                        realm.add(item2)
                    }

                    let versionResponses: [SyncObject: Any] = [.collection: [collectionKey: 2]]
                    let objectKeys: [SyncObject: String] = [.collection: collectionKey]
                    let collectionData: [[String: Any]] = [["key": collectionKey,
                                                            "version": 2,
                                                            "library": ["id": 0, "type": "user", "name": "A"],
                                                            "data": ["name": "A"]]]
                    let objectResponses: [SyncObject: Any] = [.collection: collectionData]

                    createStub(for: KeyRequest(), baseUrl: baseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys", withExtension: "json")!)
                    createStub(for: SubmitDeletionsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, objectType: .collection,
                                                                keys: [collectionKey], version: 1),
                                    baseUrl: baseUrl, headers: header, statusCode: 412, jsonResponse: [:])
                    createStub(for: SubmitDeletionsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, objectType: .item,
                                                                keys: [deletedItemKey], version: 1),
                                    baseUrl: baseUrl, headers: header, statusCode: 412, jsonResponse: [:])
                    createStub(for: GroupVersionsRequest(userId: SyncControllerSpec.userId), baseUrl: baseUrl, headers: header,
                               jsonResponse: [:])
                    objects.forEach { object in
                        createStub(for: VersionsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId,
                                                                     objectType: object, version: 1),
                                        baseUrl: baseUrl, headers: header,
                                        jsonResponse: (versionResponses[object] ?? [:]))
                    }
                    objects.forEach { object in
                        createStub(for: ObjectsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, objectType: object,
                                                            keys: (objectKeys[object] ?? "")),
                                        baseUrl: baseUrl, headers: header,
                                        jsonResponse: (objectResponses[object] ?? [:]))
                    }
                    createStub(for: SettingsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, version: 1),
                                    baseUrl: baseUrl, headers: header,
                                    jsonResponse: ["tagColors" : ["value": [["name": "A", "color": "#CC66CC"]], "version": 1]])
                    createStub(for: DeletionsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, version: 1),
                                    baseUrl: baseUrl, headers: header,
                                    jsonResponse: ["collections": [], "searches": [], "items": [], "tags": []])

                    waitUntil(timeout: 10) { doneAction in
                        SyncControllerSpec.syncController.reportFinish = { _ in
                            let realm = try! Realm(configuration: SyncControllerSpec.realmConfig)
                            realm.refresh()

                            let library = realm.objects(RCustomLibrary.self).first
                            expect(libraryId).toNot(beNil())
                            expect(library?.type).to(equal(.myLibrary))

                            expect(library?.collections.count).to(equal(1))
                            expect(library?.items.count).to(equal(2))
                            expect(realm.objects(RCollection.self).count).to(equal(1))
                            expect(realm.objects(RItem.self).count).to(equal(2))

                            let collection = realm.objects(RCollection.self).filter("key = %@", collectionKey).first
                            expect(collection).toNot(beNil())
                            expect(collection?.syncState).to(equal(.synced))
                            expect(collection?.version).to(equal(2))
                            expect(collection?.deleted).to(beFalse())
                            expect(collection?.customLibrary?.type).to(equal(.myLibrary))
                            expect(collection?.parent).to(beNil())
                            expect(collection?.items.count).to(equal(2))
                            if let collection = collection {
                                expect(collection.items.map({ $0.key })).to(contain(["BBBBBBBB", "CCCCCCCC"]))
                            }

                            let item = realm.objects(RItem.self).filter("key = %@", "CCCCCCCC").first
                            expect(item).toNot(beNil())
                            expect(item?.deleted).to(beFalse())

                            doneAction()
                        }

                        SyncControllerSpec.syncController.start(type: .normal, libraries: .all)
                    }
                }
            }

            describe("Upload") {
                it("should update collection and item") {
                    let oldVersion = 3
                    let newVersion = oldVersion + 1
                    let collectionKey = "AAAAAAAA"
                    let itemKey = "BBBBBBBB"

                    SyncControllerSpec.createNewSyncController()

                    let realm = SyncControllerSpec.realm!
                    try! realm.write {
                        let library = realm.object(ofType: RCustomLibrary.self,
                                                   forPrimaryKey: RCustomLibraryType.myLibrary.rawValue)

                        let versions = RVersions()
                        versions.collections = oldVersion
                        versions.items = oldVersion
                        realm.add(versions)
                        library?.versions = versions

                        let collection = RCollection()
                        collection.key = collectionKey
                        collection.name = "New name"
                        collection.version = oldVersion
                        collection.changedFields = .name
                        collection.customLibrary = library
                        realm.add(collection)

                        let item = RItem()
                        item.key = itemKey
                        item.syncState = .synced
                        item.version = oldVersion
                        item.changedFields = .fields
                        item.customLibrary = library
                        realm.add(item)

                        let titleField = RItemField()
                        titleField.key = "title"
                        titleField.value = "New item"
                        titleField.changed = true
                        titleField.item = item
                        realm.add(titleField)

                        let pageField = RItemField()
                        pageField.key = "numPages"
                        pageField.value = "1"
                        pageField.changed = true
                        pageField.item = item
                        realm.add(pageField)

                        let unchangedField = RItemField()
                        unchangedField.key = "callNumber"
                        unchangedField.value = "somenumber"
                        unchangedField.changed = false
                        unchangedField.item = item
                        realm.add(unchangedField)
                    }

                    let libraryId = SyncControllerSpec.userLibraryId

                    let collectionUpdate = UpdatesRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, objectType: .collection,
                                                          params: [], version: oldVersion)
                    // We don't care about specific params, we just want to catch update for all objecfts of this type
                    let collectionConditions = collectionUpdate.stubCondition(with: baseUrl, ignorePostParams: true)
                    stub(condition: collectionConditions, response: { request -> HTTPStubsResponse in
                        let params = request.httpBodyStream.flatMap({ self.jsonParameters(from: $0) })
                        expect(params?.count).to(equal(1))
                        let firstParams = params?.first ?? [:]
                        expect(firstParams["key"] as? String).to(equal(collectionKey))
                        expect(firstParams["version"] as? Int).to(equal(oldVersion))
                        expect(firstParams["name"] as? String).to(equal("New name"))
                        return HTTPStubsResponse(jsonObject: ["success": ["0": [:]], "unchanged": [], "failed": []],
                                                 statusCode: 200, headers: ["last-modified-version": "\(newVersion)"])
                    })

                    let itemUpdate = UpdatesRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, objectType: .item,
                                                    params: [], version: oldVersion)
                    // We don't care about specific params, we just want to catch update for all objecfts of this type
                    let itemConditions = itemUpdate.stubCondition(with: baseUrl, ignorePostParams: true)
                    stub(condition: itemConditions, response: { request -> HTTPStubsResponse in
                        let params = request.httpBodyStream.flatMap({ self.jsonParameters(from: $0) })
                        expect(params?.count).to(equal(1))
                        let firstParams = params?.first ?? [:]
                        expect(firstParams["key"] as? String).to(equal(itemKey))
                        expect(firstParams["version"] as? Int).to(equal(oldVersion))
                        expect(firstParams["title"] as? String).to(equal("New item"))
                        expect(firstParams["numPages"] as? String).to(equal("1"))
                        expect(firstParams["callNumber"]).to(beNil())
                        return HTTPStubsResponse(jsonObject: ["success": ["0": [:]], "unchanged": [], "failed": []],
                                                 statusCode: 200, headers: ["last-modified-version": "\(newVersion)"])
                    })
                    createStub(for: KeyRequest(), baseUrl: baseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys", withExtension: "json")!)

                    waitUntil(timeout: 10) { doneAction in
                        SyncControllerSpec.syncController.reportFinish = { _ in
                            let realm = try! Realm(configuration: SyncControllerSpec.realmConfig)
                            realm.refresh()

                            let library = realm.object(ofType: RCustomLibrary.self,
                                                       forPrimaryKey: RCustomLibraryType.myLibrary.rawValue)

                            let versions = library?.versions
                            expect(versions?.collections).to(equal(newVersion))
                            expect(versions?.items).to(equal(newVersion))

                            let collection = realm.objects(RCollection.self).filter(.key(collectionKey, in: .custom(.myLibrary))).first
                            expect(collection?.version).to(equal(newVersion))
                            expect(collection?.rawChangedFields).to(equal(0))

                            let item = realm.objects(RItem.self).filter(.key(itemKey, in: .custom(.myLibrary))).first
                            expect(item?.version).to(equal(newVersion))
                            expect(item?.rawChangedFields).to(equal(0))
                            item?.fields.forEach({ field in
                                expect(field.changed).to(beFalse())
                            })

                            doneAction()
                        }
                        SyncControllerSpec.syncController.start(type: .normal, libraries: .specific([.custom(.myLibrary)]))
                    }
                }

                it("should upload child item after parent item") {
                    let oldVersion = 3
                    let newVersion = oldVersion + 1
                    let parentKey = "BBBBBBBB"
                    let childKey = "CCCCCCCC"
                    let otherKey = "AAAAAAAA"

                    SyncControllerSpec.createNewSyncController()

                    let realm = SyncControllerSpec.realm!
                    try! realm.write {
                        let library = realm.object(ofType: RCustomLibrary.self,
                                                   forPrimaryKey: RCustomLibraryType.myLibrary.rawValue)

                        let versions = RVersions()
                        versions.collections = oldVersion
                        versions.items = oldVersion
                        realm.add(versions)
                        library?.versions = versions

                        // Items created one after another, then CCCCCCCC has been updated and added
                        // as a child to BBBBBBBB, then AAAAAAAA has been updated and then BBBBBBBB has been updated
                        // AAAAAAAA is without a child, BBBBBBBB has child CCCCCCCC,
                        // BBBBBBBB has been updated after child CCCCCCCC, but BBBBBBBB should appear in parameters
                        // before CCCCCCCC because it is a parent

                        let item = RItem()
                        item.key = otherKey
                        item.syncState = .synced
                        item.version = oldVersion
                        item.changedFields = .all
                        item.dateAdded = Date(timeIntervalSinceNow: -3600)
                        item.dateModified = Date(timeIntervalSinceNow: -1800)
                        item.customLibrary = library
                        realm.add(item)

                        let item2 = RItem()
                        item2.key = parentKey
                        item2.syncState = .synced
                        item2.version = oldVersion
                        item2.changedFields = .all
                        item2.dateAdded = Date(timeIntervalSinceNow: -3599)
                        item2.dateModified = Date(timeIntervalSinceNow: -60)
                        item2.customLibrary = library
                        realm.add(item2)

                        let item3 = RItem()
                        item3.key = childKey
                        item3.syncState = .synced
                        item3.version = oldVersion
                        item3.changedFields = .all
                        item3.dateAdded = Date(timeIntervalSinceNow: -3598)
                        item3.dateModified = Date(timeIntervalSinceNow: -3540)
                        item3.customLibrary = library
                        item3.parent = item2
                        realm.add(item3)
                    }

                    let libraryId = SyncControllerSpec.userLibraryId

                    let update = UpdatesRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, objectType: .item,
                                                params: [], version: oldVersion)
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

                        return HTTPStubsResponse(jsonObject: ["success": ["0": [:]], "unchanged": [], "failed": []],
                                                   statusCode: 200, headers: ["last-modified-version": "\(newVersion)"])
                    })
                    createStub(for: KeyRequest(), baseUrl: baseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys", withExtension: "json")!)

                    waitUntil(timeout: 10) { doneAction in
                        SyncControllerSpec.syncController.reportFinish = { _ in
                            doneAction()
                        }
                        SyncControllerSpec.syncController.start(type: .normal, libraries: .specific([.custom(.myLibrary)]))
                    }
                }

                it("should upload child collection after parent collection") {
                    let oldVersion = 3
                    let newVersion = oldVersion + 1
                    let firstKey = "AAAAAAAA"
                    let secondKey = "BBBBBBBB"
                    let thirdKey = "CCCCCCCC"

                    SyncControllerSpec.createNewSyncController()

                    let realm = SyncControllerSpec.realm!
                    try! realm.write {
                        let library = realm.object(ofType: RCustomLibrary.self,
                                                   forPrimaryKey: RCustomLibraryType.myLibrary.rawValue)

                        let versions = RVersions()
                        versions.collections = oldVersion
                        versions.items = oldVersion
                        realm.add(versions)
                        library?.versions = versions

                        // Collections created in order: CCCCCCCC, BBBBBBBB, AAAAAAAA
                        // modified in order: BBBBBBBB, AAAAAAAA, CCCCCCCC
                        // but should be processed in order AAAAAAAA, BBBBBBBB, CCCCCCCC because A is a parent of B
                        // and B is a parent of C

                        let collection = RCollection()
                        let collection2 = RCollection()
                        let collection3 = RCollection()

                        realm.add(collection3)
                        realm.add(collection2)
                        realm.add(collection)

                        collection.key = firstKey
                        collection.syncState = .synced
                        collection.version = oldVersion
                        collection.changedFields = .all
                        collection.dateModified = Date(timeIntervalSinceNow: -1800)
                        collection.customLibrary = library

                        collection2.key = secondKey
                        collection2.syncState = .synced
                        collection2.version = oldVersion
                        collection2.changedFields = .all
                        collection2.dateModified = Date(timeIntervalSinceNow: -3540)
                        collection2.customLibrary = library
                        collection2.parent = collection

                        collection3.key = thirdKey
                        collection3.syncState = .synced
                        collection3.version = oldVersion
                        collection3.changedFields = .all
                        collection3.dateModified = Date(timeIntervalSinceNow: -60)
                        collection3.customLibrary = library
                        collection3.parent = collection2
                    }

                    let libraryId = SyncControllerSpec.userLibraryId

                    let update = UpdatesRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, objectType: .collection,
                                                params: [], version: oldVersion)
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

                        return HTTPStubsResponse(jsonObject: ["success": ["0": [:]], "unchanged": [], "failed": []],
                                                   statusCode: 200, headers: ["last-modified-version": "\(newVersion)"])
                    })
                    createStub(for: KeyRequest(), baseUrl: baseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys", withExtension: "json")!)

                    SyncControllerSpec.createNewSyncController()

                    waitUntil(timeout: 10) { doneAction in
                        SyncControllerSpec.syncController.reportFinish = { _ in
                            doneAction()
                        }
                        SyncControllerSpec.syncController.start(type: .normal, libraries: .specific([.custom(.myLibrary)]))
                    }
                }

                it("should update library version after upload") {
                    let oldVersion = 3
                    let newVersion = oldVersion + 10

                    SyncControllerSpec.createNewSyncController()

                    let realm = SyncControllerSpec.realm!
                    try! realm.write {
                        let library = realm.object(ofType: RCustomLibrary.self,
                                                   forPrimaryKey: RCustomLibraryType.myLibrary.rawValue)

                        let versions = RVersions()
                        versions.collections = oldVersion
                        versions.items = oldVersion
                        realm.add(versions)
                        library?.versions = versions

                        let collection = RCollection()
                        realm.add(collection)

                        collection.key = "AAAAAAAA"
                        collection.syncState = .synced
                        collection.version = oldVersion
                        collection.changedFields = .all
                        collection.dateModified = Date()
                        collection.customLibrary = library
                    }

                    let libraryId = SyncControllerSpec.userLibraryId

                    let update = UpdatesRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, objectType: .collection,
                                                params: [], version: oldVersion)
                    createStub(for: KeyRequest(), baseUrl: baseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys", withExtension: "json")!)
                    // We don't care about specific post params, we just need to catch all updates for given type
                    createStub(for: update, ignorePostParams: true, baseUrl: baseUrl,
                               headers: ["last-modified-version": "\(newVersion)"],
                               statusCode: 200,
                               jsonResponse: ["success": ["0": [:]], "unchanged": [], "failed": []])

                    waitUntil(timeout: 10) { doneAction in
                        SyncControllerSpec.syncController.reportFinish = { _ in
                            let realm = try! Realm(configuration: SyncControllerSpec.realmConfig)
                            realm.refresh()

                            let library = realm.object(ofType: RCustomLibrary.self,
                                                       forPrimaryKey: RCustomLibraryType.myLibrary.rawValue)

                            expect(library?.versions?.collections).to(equal(newVersion))

                            doneAction()
                        }
                        SyncControllerSpec.syncController.start(type: .normal, libraries: .specific([.custom(.myLibrary)]))
                    }
                }

                it("should process downloads after upload failure") {
                    let header = ["last-modified-version" : "3"]
                    let libraryId = SyncControllerSpec.userLibraryId
                    let objects = SyncObject.allCases

                    var downloadCalled = false

                    var statusCode: Int32 = 412
                    let request = UpdatesRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, objectType: .item, params: [], version: 0)
                    stub(condition: request.stubCondition(with: baseUrl), response: { _ -> HTTPStubsResponse in
                        let code = statusCode
                        statusCode = 200
                        return HTTPStubsResponse(jsonObject: [:], statusCode: code, headers: header)
                    })
                    createStub(for: GroupVersionsRequest(userId: SyncControllerSpec.userId),
                               baseUrl: baseUrl, headers: header, jsonResponse: [:])
                    objects.forEach { object in
                        createStub(for: VersionsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId,
                                                                     objectType: object, version: 0),
                                        baseUrl: baseUrl, headers: header, jsonResponse: [:])
                    }
                    stub(condition: SettingsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, version: 0).stubCondition(with: baseUrl),
                         response: { _ -> HTTPStubsResponse in
                        downloadCalled = true
                        return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: header)
                    })
                    createStub(for: KeyRequest(), baseUrl: baseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys", withExtension: "json")!)
                    createStub(for: DeletionsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    jsonResponse: ["collections": [], "searches": [], "items": [], "tags": []])

                    SyncControllerSpec.createNewSyncController()

                    waitUntil(timeout: 10) { doneAction in
                        SyncControllerSpec.syncController.reportFinish = { _ in
                            expect(downloadCalled).to(beTrue())
                            doneAction()
                        }

                        SyncControllerSpec.syncController.start(type: .normal, libraries: .all)
                    }
                }

                it("should upload local deletions") {
                    let header = ["last-modified-version" : "1"]
                    let libraryId = SyncControllerSpec.userLibraryId
                    let collectionKey = "AAAAAAAA"
                    let searchKey = "BBBBBBBB"
                    let itemKey = "CCCCCCCC"

                    SyncControllerSpec.createNewSyncController()

                    let realm = SyncControllerSpec.realm!
                    try! realm.write {
                        let library = realm.object(ofType: RCustomLibrary.self,
                                                   forPrimaryKey: RCustomLibraryType.myLibrary.rawValue)

                        let versions = RVersions()
                        realm.add(versions)
                        library?.versions = versions

                        let collection = RCollection()
                        collection.key = collectionKey
                        collection.name = "Deleted collection"
                        collection.version = 0
                        collection.deleted = true
                        collection.customLibrary = library
                        realm.add(collection)

                        let item = RItem()
                        item.key = itemKey
                        item.baseTitle = "Deleted item"
                        item.deleted = true
                        item.customLibrary = library
                        item.collections.append(collection)
                        realm.add(item)

                        let search = RSearch()
                        search.key = searchKey
                        search.name = "Deleted search"
                        search.deleted = true
                        search.customLibrary = library
                        realm.add(search)
                    }

                    createStub(for: KeyRequest(), baseUrl: baseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys", withExtension: "json")!)
                    createStub(for: SubmitDeletionsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, objectType: .collection,
                                                                keys: [collectionKey], version: 0),
                                    baseUrl: baseUrl, headers: header, jsonResponse: [:])
                    createStub(for: SubmitDeletionsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, objectType: .search,
                                                                keys: [searchKey], version: 0),
                                    baseUrl: baseUrl, headers: header, jsonResponse: [:])
                    createStub(for: SubmitDeletionsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, objectType: .item,
                                                                keys: [itemKey], version: 0),
                                    baseUrl: baseUrl, headers: header, jsonResponse: [:])

                    waitUntil(timeout: 10) { doneAction in
                        SyncControllerSpec.syncController.reportFinish = { _ in
                            let realm = try! Realm(configuration: SyncControllerSpec.realmConfig)
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

                        SyncControllerSpec.syncController.start(type: .normal, libraries: .all)
                    }
                }

                // TODO: Enable when proper CR is implemented
//                it("should delay on second upload conflict") {
//                    let header = ["last-modified-version" : "3"]
//                    let libraryId = SyncControllerSpec.userLibraryId
//                    let itemToDelete = "DDDDDDDD"
//                    let objects = SyncObject.allCases
//
//                    let realm = SyncControllerSpec.realm
//                    try! realm.write {
//                        let myLibrary = SyncControllerSpec.realm.objects(RCustomLibrary.self).first
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
//                    let request = UpdatesRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, objectType: .item, params: [], version: 0)
//                    // We don't care about specific params, we just need to count all update requests
//                    let condition = request.stubCondition(with: baseUrl, ignorePostParams: true)
//                    stub(condition: condition, response: { _ -> HTTPStubsResponse in
//                        retryCount += 1
//                        return HTTPStubsResponse(jsonObject: [:], statusCode: (retryCount <= 2 ? 412 : 200), headers: header)
//                    })
//                    objects.forEach { object in
//                        let version: Int? = object == .group ? nil : 0
//                        createStub(for: VersionsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId,
//                                                                     objectType: object, version: version),
//                                        baseUrl: baseUrl, headers: header,
//                                        response: [:])
//                    }
//                    createStub(for: KeyRequest(), baseUrl: baseUrl, response: ["access": ["":""]])
//                    createStub(for: SettingsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, version: 0),
//                                    baseUrl: baseUrl, headers: header,
//                                    response: ["tagColors" : ["value": [], "version": 2]])
//                    createStub(for: DeletionsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, version: 0),
//                                    baseUrl: baseUrl, headers: header,
//                                    response: ["collections": [], "searches": [], "items": [itemToDelete], "tags": []])
//
//                    var lastDelay: Int?
//                    self.controller = SyncController(userId: SyncControllerSpec.userId,
//                                                     handler: SyncControllerSpec.syncHandler,
//                                                     conflictDelays: SyncControllerSpec.delays)
//                    self.controller?.reportDelay = { delay in
//                        lastDelay = delay
//                    }
//
//                    waitUntil(timeout: 1000) { doneAction in
//                        self.controller?.reportFinish = { _ in
//                            expect(lastDelay).to(equal(1))
//                            expect(retryCount).to(equal(3))
//
//                            let realm = try! Realm(configuration: SyncControllerSpec.realmConfig)
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

            it("should make only one request if in sync") {
                let libraryId = SyncControllerSpec.userLibraryId
                let expected: [SyncController.Action] = [.loadKeyPermissions, .syncGroupVersions,
                                                         .createLibraryActions(.all, .automatic), .syncSettings(libraryId, 0)]

                createStub(for: KeyRequest(), baseUrl: baseUrl, url: Bundle(for: type(of: self)).url(forResource: "test_keys", withExtension: "json")!)
                createStub(for: GroupVersionsRequest(userId: SyncControllerSpec.userId),
                           baseUrl: baseUrl, headers: nil, statusCode: 200, jsonResponse: [:])
                createStub(for: SettingsRequest(libraryId: libraryId, userId: SyncControllerSpec.userId, version: 0),
                           baseUrl: baseUrl, statusCode: 304, jsonResponse: [:])

                SyncControllerSpec.createNewSyncController()

                waitUntil(timeout: 10) { doneAction in
                    SyncControllerSpec.syncController.reportFinish = { result in
                        switch result {
                        case .success(let data):
                            expect(data.0).to(equal(expected))
                        case .failure(let error):
                            fail("Failure: \(error)")
                        }

                        doneAction()
                    }

                    SyncControllerSpec.syncController.start(type: .normal, libraries: .all)
                }
            }
        }
    }

    private func jsonParameters(from stream: InputStream) -> [[String: Any]] {
        let json = try? JSONSerialization.jsonObject(with: stream.data, options: .allowFragments)
        return (json as? [[String: Any]]) ?? []
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
