//
//  SyncControllerSpec.swift
//  ZoteroTests
//
//  Created by Michal Rentka on 08/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

@testable import Zotero

import CocoaLumberjack
import Nimble
import OHHTTPStubs
import RealmSwift
import RxSwift
import Quick

class SyncControllerSpec: QuickSpec {
    fileprivate static let groupId = 10
    private static let userId = 100
    private static let realmConfig = Realm.Configuration(inMemoryIdentifier: "TestsRealmConfig")
    private static let realm = try! Realm(configuration: realmConfig) // Retain realm with inMemoryIdentifier so that data are not deleted
    private static let syncHandler = SyncActionHandlerController(userId: userId,
                                                                 apiClient: ZoteroApiClient(baseUrl: ApiConstants.baseUrlString),
                                                                 dbStorage: RealmDbStorage(config: realmConfig),
                                                                 fileStorage: TestFileStorage())

    fileprivate static var syncVersionData: (Int, Int) = (0, 0) // version, object count
    fileprivate static var expectedKeys: [String] = []
    fileprivate static var groupIdVersions: Versions = Versions(collections: 0, items: 0, trash: 0, searches: 0,
                                                                deletions: 0, settings: 0)
    private var controller: SyncController?

    override func spec() {

        beforeEach {
            OHHTTPStubs.removeAllStubs()
            self.controller = nil

            let realm = SyncControllerSpec.realm
            try! realm.write {
                realm.deleteAll()

                let myLibrary = RLibrary()
                myLibrary.identifier = RLibrary.myLibraryId
                myLibrary.name = "My Library"
                realm.add(myLibrary)
            }
        }

        describe("Queue") {
            describe("action processing") {
                it("processes store version action") {
                    let initial: [QueueAction] = [.storeVersion(3, .group(SyncControllerSpec.groupId), .collection)]
                    let expected: [QueueAction] = initial
                    var all: [QueueAction]?

                    self.controller = self.performActionsTest(queue: initial,
                                                              result: { _ in
                                                                  return Single.just(())
                                                              }, check: { result in
                                                                  all = result
                                                              })

                    expect(all).toEventually(equal(expected))
                }

                it("processes download batch action") {
                    let action = ObjectBatch(order: 0, library: .user(SyncControllerSpec.userId),
                                             object: .group, keys: [1], version: 0)
                    let initial: [QueueAction] = [.syncBatchToFile(action)]
                    let expected: [QueueAction] = initial
                    var all: [QueueAction]?

                    self.controller = self.performActionsTest(queue: initial,
                                                              result: { _ in
                                                                  return Single.just(())
                                                              }, check: { result in
                                                                  all = result
                                                              })

                    expect(all).toEventually(equal(expected))
                }

                it("processes sync batch to db") {
                    let action = ObjectBatch(order: 0, library: .user(SyncControllerSpec.userId),
                                             object: .group, keys: [1], version: 0)
                    let initial: [QueueAction] = [.syncBatchToDb(action)]
                    let expected: [QueueAction] = initial
                    var all: [QueueAction]?

                    self.controller = self.performActionsTest(queue: initial,
                                                              result: { _ in
                                                                  return Single.just(())
                                                              }, check: { result in
                                                                  all = result
                                                              })

                    expect(all).toEventually(equal(expected))
                }

                it("processes sync versions (collection) action") {
                    SyncControllerSpec.syncVersionData = (3, 35)

                    let library = SyncLibraryType.user(SyncControllerSpec.userId)
                    let keys1 = (0..<5).map({ $0.description })
                    let keys2 = (5..<15).map({ $0.description })
                    let keys3 = (15..<35).map({ $0.description })
                    let initial: [QueueAction] = [.syncVersions(.user(SyncControllerSpec.userId), .collection, 2)]
                    let expected: [QueueAction] = [.syncVersions(.user(SyncControllerSpec.userId), .collection, 2),
                                                   .syncBatchToFile(ObjectBatch(order: 0, library: library,
                                                                                  object: .collection,
                                                                                  keys: keys1,
                                                                                  version: 3)),
                                                   .syncBatchToDb(ObjectBatch(order: 0, library: library,
                                                                              object: .collection,
                                                                              keys: keys1,
                                                                              version: 3)),
                                                   .syncBatchToFile(ObjectBatch(order: 1, library: library,
                                                                                object: .collection,
                                                                                keys: keys2,
                                                                                version: 3)),
                                                   .syncBatchToDb(ObjectBatch(order: 1, library: library,
                                                                              object: .collection,
                                                                              keys: keys2,
                                                                              version: 3)),
                                                   .syncBatchToFile(ObjectBatch(order: 2, library: library,
                                                                                object: .collection,
                                                                                keys: keys3,
                                                                                version: 3)),
                                                   .syncBatchToDb(ObjectBatch(order: 2, library: library,
                                                                              object: .collection,
                                                                              keys: keys3,
                                                                              version: 3)),
                                                   .storeVersion(3, .user(SyncControllerSpec.userId), .collection)]
                    var all: [QueueAction]?

                    self.controller = self.performActionsTest(queue: initial,
                                                              result: { _ in
                                                                  return Single.just(())
                                                              }, check: { result in
                                                                  all = result
                                                              })

                    expect(all).toEventually(equal(expected))
                }

                it("processes create groups action") {
                    SyncControllerSpec.syncVersionData = (3, 1)
                    SyncControllerSpec.groupIdVersions = Versions(collections: 2, items: 1, trash: 1, searches: 1,
                                                                  deletions: 1, settings: 1)

                    let groupId = SyncControllerSpec.groupId
                    let initial: [QueueAction] = [.createLibraryActions]
                    let expected: [QueueAction] = [.createLibraryActions,
                                                   .syncSettings(.group(groupId), 1),
                                                   .storeSettingsVersion(3, .group(groupId)),
                                                   .syncVersions(.group(groupId), .collection, 2),
                                                   .syncBatchToFile(ObjectBatch(order: 0, library: .group(groupId),
                                                                                  object: .collection,
                                                                                  keys: ["0"],
                                                                                  version: 3)),
                                                   .syncBatchToDb(ObjectBatch(order: 0, library: .group(groupId),
                                                                                object: .collection,
                                                                                keys: ["0"],
                                                                                version: 3)),
                                                   .storeVersion(3, .group(groupId), .collection),
                                                   .syncVersions(.group(groupId), .search, 1),
                                                   .syncBatchToFile(ObjectBatch(order: 0, library: .group(groupId),
                                                                                object: .search,
                                                                                keys: ["0"],
                                                                                version: 3)),
                                                   .syncBatchToDb(ObjectBatch(order: 0, library: .group(groupId),
                                                                              object: .search,
                                                                              keys: ["0"],
                                                                              version: 3)),
                                                   .storeVersion(3, .group(groupId), .search),
                                                   .syncVersions(.group(groupId), .item, 1),
                                                   .syncBatchToFile(ObjectBatch(order: 0, library: .group(groupId),
                                                                                  object: .item,
                                                                                  keys: ["0"],
                                                                                  version: 3)),
                                                   .syncBatchToDb(ObjectBatch(order: 0, library: .group(groupId),
                                                                                object: .item,
                                                                                keys: ["0"],
                                                                                version: 3)),
                                                   .storeVersion(3, .group(groupId), .item),
                                                   .syncVersions(.group(groupId), .trash, 1),
                                                   .syncBatchToFile(ObjectBatch(order: 0, library: .group(groupId),
                                                                                  object: .trash,
                                                                                  keys: ["0"],
                                                                                  version: 3)),
                                                   .syncBatchToDb(ObjectBatch(order: 0, library: .group(groupId),
                                                                                object: .trash,
                                                                                keys: ["0"],
                                                                                version: 3)),
                                                   .storeVersion(3, .group(groupId), .trash),
                                                   .syncDeletions(.group(groupId), 1)]
                    var all: [QueueAction]?

                    self.controller = self.performActionsTest(queue: initial,
                                                              result: { _ in
                                                                  return Single.just(())
                                                              }, check: { result in
                                                                  all = result
                                                              })

                    expect(all).toEventually(equal(expected))
                }

                it("processes sync versions (group) action") {
                    SyncControllerSpec.syncVersionData = (7, 1)
                    SyncControllerSpec.groupIdVersions = Versions(collections: 4, items: 4, trash: 2, searches: 2,
                                                                  deletions: 4, settings: 4)

                    let groupId = SyncControllerSpec.groupId
                    let initial: [QueueAction] = [.syncVersions(.user(SyncControllerSpec.userId), .group, nil)]
                    let expected: [QueueAction] = [.syncVersions(.user(SyncControllerSpec.userId), .group, nil),
                                                   .syncBatchToFile(ObjectBatch(order: 0,
                                                                                library: .user(SyncControllerSpec.userId),
                                                                                object: .group,
                                                                                keys: [0],
                                                                                version: 7)),
                                                   .syncBatchToDb(ObjectBatch(order: 0,
                                                                              library: .user(SyncControllerSpec.userId),
                                                                              object: .group,
                                                                              keys: [0],
                                                                              version: 7)),
                                                   .createLibraryActions,
                                                   .syncSettings(.group(groupId), 4),
                                                   .storeSettingsVersion(7, .group(groupId)),
                                                   .syncVersions(.group(groupId), .collection, 4),
                                                   .syncBatchToFile(ObjectBatch(order: 0, library: .group(groupId),
                                                                                object: .collection,
                                                                                keys: ["0"],
                                                                                version: 7)),
                                                   .syncBatchToDb(ObjectBatch(order: 0, library: .group(groupId),
                                                                              object: .collection,
                                                                              keys: ["0"],
                                                                              version: 7)),
                                                   .storeVersion(7, .group(groupId), .collection),
                                                   .syncVersions(.group(groupId), .search, 2),
                                                   .syncBatchToFile(ObjectBatch(order: 0, library: .group(groupId),
                                                                                object: .search,
                                                                                keys: ["0"],
                                                                                version: 7)),
                                                   .syncBatchToDb(ObjectBatch(order: 0, library: .group(groupId),
                                                                              object: .search,
                                                                              keys: ["0"],
                                                                              version: 7)),
                                                   .storeVersion(7, .group(groupId), .search),
                                                   .syncVersions(.group(groupId), .item, 4),
                                                   .syncBatchToFile(ObjectBatch(order: 0, library: .group(groupId),
                                                                                object: .item,
                                                                                keys: ["0"],
                                                                                version: 7)),
                                                   .syncBatchToDb(ObjectBatch(order: 0, library: .group(groupId),
                                                                              object: .item,
                                                                              keys: ["0"],
                                                                              version: 7)),
                                                   .storeVersion(7, .group(groupId), .item),
                                                   .syncVersions(.group(groupId), .trash, 2),
                                                   .syncBatchToFile(ObjectBatch(order: 0, library: .group(groupId),
                                                                                object: .trash,
                                                                                keys: ["0"],
                                                                                version: 7)),
                                                   .syncBatchToDb(ObjectBatch(order: 0, library: .group(groupId),
                                                                              object: .trash,
                                                                              keys: ["0"],
                                                                              version: 7)),
                                                   .storeVersion(7, .group(groupId), .trash),
                                                   .syncDeletions(.group(groupId), 4)]
                    var all: [QueueAction]?

                    self.controller = self.performActionsTest(queue: initial,
                                                              result: { _ in
                                                                  return Single.just(())
                                                              }, check: { result in
                                                                  all = result
                                                              })

                    expect(all).toEventually(equal(expected))
                }
            }

            describe("fatal error handling") {
                it("doesn't process store version action") {
                    let initial: [QueueAction] = [.storeVersion(1, .user(SyncControllerSpec.userId), .group)]
                    var error: Zotero.SyncError?

                    self.controller = self.performErrorTest(queue: initial,
                                                            result: { action in
                                                                switch action {
                                                                case .storeVersion:
                                                                    return Single.error(TestErrors.fatal)
                                                                default:
                                                                    return Single.just(())
                                                                }
                                                            }, check: { result in
                                                                error = result as? Zotero.SyncError
                                                            })

                    expect(error).toEventually(equal(SyncError.noInternetConnection))
                }

                it("doesn't process download batch action") {
                    let action = ObjectBatch(order: 0, library: .user(SyncControllerSpec.userId), object: .group,
                                             keys: [1], version: 0)
                    let initial: [QueueAction] = [.syncBatchToFile(action)]
                    var error: Zotero.SyncError?

                    self.controller = self.performErrorTest(queue: initial,
                                                            result: { action in
                                                                switch action {
                                                                case .downloadObject(let object):
                                                                    if object == .group {
                                                                        return Single.error(TestErrors.fatal)
                                                                    }
                                                                    return Single.just(())
                                                                default:
                                                                    return Single.just(())
                                                                }
                                                            }, check: { result in
                                                                error = result as? Zotero.SyncError
                                                            })

                    expect(error).toEventually(equal(SyncError.noInternetConnection))
                }

                it("doesn't process sync batch to db") {
                    let action = ObjectBatch(order: 0, library: .user(SyncControllerSpec.userId), object: .group,
                                             keys: [1], version: 0)
                    let initial: [QueueAction] = [.syncBatchToDb(action)]
                    var error: Zotero.SyncError?

                    self.controller = self.performErrorTest(queue: initial,
                                                            result: { action in
                                                                switch action {
                                                                case .storeObject(let object):
                                                                    if object == .group {
                                                                        return Single.error(TestErrors.fatal)
                                                                    }
                                                                    return Single.just(())
                                                                default:
                                                                    return Single.just(())
                                                                }
                                                            }, check: { result in
                                                                error = result as? Zotero.SyncError
                                                            })

                    expect(error).toEventually(equal(SyncError.noInternetConnection))
                }

                it("doesn't process sync versions (collection) action") {
                    SyncControllerSpec.syncVersionData = (7, 1)

                    let initial: [QueueAction] = [.syncVersions(.user(SyncControllerSpec.userId), .collection, 1)]
                    var error: Zotero.SyncError?

                    self.controller = self.performErrorTest(queue: initial,
                                                            result: { action in
                                                                switch action {
                                                                case .syncVersions(let object):
                                                                    if object == .collection {
                                                                        return Single.error(TestErrors.fatal)
                                                                    }
                                                                    return Single.just(())
                                                                default:
                                                                    return Single.just(())
                                                                }
                                                            }, check: { result in
                                                                error = result as? Zotero.SyncError
                                                            })

                    expect(error).toEventually(equal(SyncError.noInternetConnection))
                }

                it("doesn't process create groups action") {
                    SyncControllerSpec.syncVersionData = (7, 1)

                    let initial: [QueueAction] = [.createLibraryActions]
                    var error: Zotero.SyncError?

                    self.controller = self.performErrorTest(queue: initial,
                                                            result: { action in
                                                                switch action {
                                                                case .loadGroups:
                                                                    return Single.error(TestErrors.fatal)
                                                                default:
                                                                    return Single.just(())
                                                                }
                                                            }, check: { result in
                                                                error = result as? Zotero.SyncError
                                                            })

                    expect(error).toEventually(equal(SyncError.allLibrariesFetchFailed(SyncError.noInternetConnection)))
                }
            }

            describe("non-fatal error handling") {
                it("doesn't abort") {
                    SyncControllerSpec.syncVersionData = (7, 1)
                    SyncControllerSpec.groupIdVersions = Versions(collections: 4, items: 4, trash: 2, searches: 2,
                                                                  deletions: 0, settings: 0)

                    let initial: [QueueAction] = [.syncVersions(.user(SyncControllerSpec.userId), .group, nil)]
                    var didFinish: Bool?

                    self.controller = self.performActionsTest(queue: initial,
                                                              result: { action in
                                                                  switch action {
                                                                  case .syncVersions(let object):
                                                                      if object == .collection {
                                                                          return Single.error(SyncActionHandlerError.expired)
                                                                      }
                                                                  default: break
                                                                  }
                                                                  return Single.just(())
                                                              }, check: { result in
                                                                  didFinish = true
                                                              })

                    expect(didFinish).toEventually(beTrue())
                }
            }
        }

        describe("Syncing") {
            let baseUrl = URL(string: ApiConstants.baseUrlString)!

            describe("Download") {
                it("should download items into a new library", closure: {
                    let header = ["Last-Modified-Version" : "3"]
                    let library = SyncLibraryType.user(SyncControllerSpec.userId)
                    let objects = SyncObjectType.allCases

                    var versionResponses: [SyncObjectType: Any] = [:]
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
                        case .group: break
                        }
                    }

                    let objectKeys: [SyncObjectType: String] = [.collection: "AAAAAAAA",
                                                                .search: "AAAAAAAA",
                                                                .item: "AAAAAAAA",
                                                                .trash: "BBBBBBBB"]
                    var objectResponses: [SyncObjectType: Any] = [:]
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
                                                       "data": ["title": "A", "itemType": "thesis", "tags": [["tag": "A"]]]]]
                        case .trash:
                            objectResponses[object] = [["key": "BBBBBBBB",
                                                       "version": 4,
                                                       "library": ["id": 0, "type": "user", "name": "A"],
                                                       "data": ["note": "<p>This is a note</p>",
                                                                "parentItem": "AAAAAAAA",
                                                                "itemType": "note",
                                                                "deleted": 1]]]
                        case .group: break
                        }
                    }

                    objects.forEach { object in
                        self.createStub(for: VersionsRequest<String>(libraryType: library, objectType: object, version: 0),
                                        baseUrl: baseUrl, headers: header,
                                        response: (versionResponses[object] ?? [:]))
                    }
                    objects.forEach { object in
                        self.createStub(for: ObjectsRequest(libraryType: library, objectType: object, keys: (objectKeys[object] ?? "")),
                                        baseUrl: baseUrl, headers: header,
                                        response: (objectResponses[object] ?? [:]))
                    }
                    self.createStub(for: SettingsRequest(libraryType: library, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    response: ["tagColors" : ["value": [["name": "A", "color": "#CC66CC"]], "version": 2]])
                    self.createStub(for: DeletionsRequest(libraryType: library, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    response: ["collections": [], "searches": [], "items": [], "tags": []])

                    self.controller = SyncController(userId: SyncControllerSpec.userId,
                                                     handler: SyncControllerSpec.syncHandler)

                    waitUntil(timeout: 10) { doneAction in
                        self.controller?.reportFinish = { _ in
                            let realm = try! Realm(configuration: SyncControllerSpec.realmConfig)
                            realm.refresh()

                            let library = realm.objects(RLibrary.self).first
                            expect(library).toNot(beNil())
                            expect(library?.identifier).to(equal(RLibrary.myLibraryId))

                            expect(library?.collections.count).to(equal(1))
                            expect(library?.items.count).to(equal(2))
                            expect(library?.searches.count).to(equal(1))
                            expect(library?.tags.count).to(equal(1))
                            expect(realm.objects(RLibrary.self).count).to(equal(1))
                            expect(realm.objects(RCollection.self).count).to(equal(1))
                            expect(realm.objects(RSearch.self).count).to(equal(1))
                            expect(realm.objects(RItem.self).count).to(equal(2))
                            expect(realm.objects(RTag.self).count).to(equal(1))

                            let versions = library?.versions
                            expect(versions).toNot(beNil())
                            expect(versions?.collections).to(equal(3))
                            expect(versions?.deletions).to(equal(3))
                            expect(versions?.items).to(equal(3))
                            expect(versions?.searches).to(equal(3))
                            expect(versions?.settings).to(equal(3))
                            expect(versions?.trash).to(equal(3))

                            let collection = realm.objects(RCollection.self).first
                            expect(collection?.key).to(equal("AAAAAAAA"))
                            expect(collection?.name).to(equal("A"))
                            expect(collection?.needsSync).to(beFalse())
                            expect(collection?.version).to(equal(1))
                            expect(collection?.library?.identifier).to(equal(RLibrary.myLibraryId))
                            expect(collection?.parent).to(beNil())
                            expect(collection?.children.count).to(equal(0))

                            let item = realm.objects(RItem.self).filter("key = %@", "AAAAAAAA").first
                            expect(item).toNot(beNil())
                            expect(item?.title).to(equal("A"))
                            expect(item?.version).to(equal(3))
                            expect(item?.trash).to(beFalse())
                            expect(item?.needsSync).to(beFalse())
                            expect(item?.library?.identifier).to(equal(RLibrary.myLibraryId))
                            expect(item?.collections.count).to(equal(0))
                            expect(item?.fields.count).to(equal(1))
                            expect(item?.fields.first?.key).to(equal("title"))
                            expect(item?.parent).to(beNil())
                            expect(item?.children.count).to(equal(1))
                            expect(item?.tags.count).to(equal(1))
                            expect(item?.tags.first?.name).to(equal("A"))

                            let item2 = realm.objects(RItem.self).filter("key = %@", "BBBBBBBB").first
                            expect(item2).toNot(beNil())
                            expect(item2?.title).to(equal("This is a note"))
                            expect(item2?.version).to(equal(4))
                            expect(item2?.trash).to(beTrue())
                            expect(item2?.needsSync).to(beFalse())
                            expect(item2?.library?.identifier).to(equal(RLibrary.myLibraryId))
                            expect(item2?.collections.count).to(equal(0))
                            expect(item?.fields.count).to(equal(1))
                            expect(item2?.parent?.key).to(equal("AAAAAAAA"))
                            expect(item2?.children.count).to(equal(0))
                            expect(item2?.tags.count).to(equal(0))
                            let noteField = item2?.fields.first
                            expect(noteField?.key).to(equal("note"))
                            expect(noteField?.value).to(equal("<p>This is a note</p>"))

                            let search = realm.objects(RSearch.self).first
                            expect(search?.key).to(equal("AAAAAAAA"))
                            expect(search?.version).to(equal(2))
                            expect(search?.name).to(equal("A"))
                            expect(search?.needsSync).to(beFalse())
                            expect(search?.library?.identifier).to(equal(RLibrary.myLibraryId))
                            expect(search?.conditions.count).to(equal(1))
                            let condition = search?.conditions.first
                            expect(condition?.condition).to(equal("itemType"))
                            expect(condition?.operator).to(equal("is"))
                            expect(condition?.value).to(equal("thesis"))

                            let tag = realm.objects(RTag.self).first
                            expect(tag?.name).to(equal("A"))
                            expect(tag?.color).to(equal("#CC66CC"))
                            expect(tag?.items.count).to(equal(1))

                            doneAction()
                        }

                        self.controller?.start()
                    }
                })

                it("should download items into a new read-only group", closure: {
                    let header = ["Last-Modified-Version" : "3"]
                    let groupId = 123
                    let library = SyncLibraryType.group(groupId)
                    let objects = SyncObjectType.allCases

                    var versionResponses: [SyncObjectType: Any] = [:]
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
                        case .group:
                            versionResponses[object] = [groupId.description: 2]
                        }
                    }

                    let objectKeys: [SyncObjectType: String] = [.collection: "AAAAAAAA",
                                                                .search: "AAAAAAAA",
                                                                .item: "AAAAAAAA",
                                                                .trash: "BBBBBBBB",
                                                                .group: groupId.description]
                    var objectResponses: [SyncObjectType: Any] = [:]
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
                                                        "data": ["title": "A", "itemType": "thesis", "tags": [["tag": "A"]]]]]
                        case .trash:
                            objectResponses[object] = [["key": "BBBBBBBB",
                                                        "version": 4,
                                                        "library": ["id": groupId, "type": "group", "name": "A"],
                                                        "data": ["note": "<p>This is a note</p>",
                                                                 "parentItem": "AAAAAAAA",
                                                                 "itemType": "note",
                                                                 "deleted": 1]]]
                        case .group:
                            objectResponses[object] = ["id": groupId,
                                                       "version": 2,
                                                       "data": ["name": "Group",
                                                                "owner": SyncControllerSpec.userId,
                                                                "type": "Private",
                                                                "description": "",
                                                                "libraryEditing": "members",
                                                                "libraryReading": "members",
                                                                "fileEditing": "members"]]
                        }
                    }

                    let myLibrary = SyncLibraryType.user(SyncControllerSpec.userId)
                    objects.forEach { object in
                        if object == .group {
                            self.createStub(for: VersionsRequest<String>(libraryType: myLibrary, objectType: object, version: nil),
                                            baseUrl: baseUrl, headers: header,
                                            response: (versionResponses[object] ?? [:]))
                        } else {
                            self.createStub(for: VersionsRequest<String>(libraryType: myLibrary, objectType: object, version: 0),
                                            baseUrl: baseUrl, headers: header, response: [:])
                        }
                    }
                    self.createStub(for: ObjectsRequest(libraryType: myLibrary, objectType: .group, keys: (objectKeys[.group] ?? "")),
                                    baseUrl: baseUrl, headers: header,
                                    response: (objectResponses[.group] ?? [:]))
                    for object in objects {
                        if object == .group { continue }
                        self.createStub(for: VersionsRequest<String>(libraryType: library, objectType: object, version: 0),
                                        baseUrl: baseUrl, headers: header,
                                        response: (versionResponses[object] ?? [:]))
                    }
                    for object in objects {
                        if object == .group { continue }
                        self.createStub(for: ObjectsRequest(libraryType: library, objectType: object, keys: (objectKeys[object] ?? "")),
                                        baseUrl: baseUrl, headers: header,
                                        response: (objectResponses[object] ?? [:]))
                    }
                    self.createStub(for: SettingsRequest(libraryType: myLibrary, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    response: ["tagColors" : ["value": [], "version": 2]])
                    self.createStub(for: SettingsRequest(libraryType: library, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    response: ["tagColors" : ["value": [["name": "A", "color": "#CC66CC"]], "version": 2]])
                    self.createStub(for: DeletionsRequest(libraryType: myLibrary, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    response: ["collections": [], "searches": [], "items": [], "tags": []])
                    self.createStub(for: DeletionsRequest(libraryType: library, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    response: ["collections": [], "searches": [], "items": [], "tags": []])

                    self.controller = SyncController(userId: SyncControllerSpec.userId,
                                                     handler: SyncControllerSpec.syncHandler)

                    waitUntil(timeout: 10) { doneAction in
                        self.controller?.reportFinish = { _ in
                            let realm = try! Realm(configuration: SyncControllerSpec.realmConfig)
                            realm.refresh()

                            let myLibrary = realm.object(ofType: RLibrary.self, forPrimaryKey: RLibrary.myLibraryId)
                            expect(myLibrary).toNot(beNil())
                            expect(myLibrary?.collections.count).to(equal(0))
                            expect(myLibrary?.items.count).to(equal(0))
                            expect(myLibrary?.searches.count).to(equal(0))
                            expect(myLibrary?.tags.count).to(equal(0))

                            let group = realm.object(ofType: RLibrary.self, forPrimaryKey: groupId)
                            expect(group).toNot(beNil())
                            expect(group?.collections.count).to(equal(1))
                            expect(group?.items.count).to(equal(2))
                            expect(group?.searches.count).to(equal(1))
                            expect(group?.tags.count).to(equal(1))

                            let versions = group?.versions
                            expect(versions).toNot(beNil())
                            expect(versions?.collections).to(equal(3))
                            expect(versions?.deletions).to(equal(3))
                            expect(versions?.items).to(equal(3))
                            expect(versions?.searches).to(equal(3))
                            expect(versions?.settings).to(equal(3))
                            expect(versions?.trash).to(equal(3))

                            let collection = realm.objects(RCollection.self)
                                                  .filter("key = %@ AND library.identifier = %d", "AAAAAAAA", groupId).first
                            expect(collection).toNot(beNil())
                            let item = realm.objects(RItem.self)
                                            .filter("key = %@ AND library.identifier = %d", "AAAAAAAA", groupId).first
                            expect(item).toNot(beNil())
                            let item2 = realm.objects(RItem.self)
                                             .filter("key = %@ AND library.identifier = %d", "BBBBBBBB", groupId).first
                            expect(item2).toNot(beNil())
                            let search = realm.objects(RSearch.self)
                                              .filter("key = %@ AND library.identifier = %d", "AAAAAAAA", groupId).first
                            expect(search).toNot(beNil())
                            let tag = realm.objects(RTag.self)
                                           .filter("name = %@ AND library.identifier = %d", "A", groupId).first
                            expect(tag).toNot(beNil())

                            doneAction()
                        }

                        self.controller?.start()
                    }
                })

                it("should apply remote deletions", closure: {
                    let header = ["Last-Modified-Version" : "3"]
                    let library = SyncLibraryType.user(SyncControllerSpec.userId)
                    let itemToDelete = "CCCCCCCC"
                    let objects = SyncObjectType.allCases

                    let realm = SyncControllerSpec.realm
                    try! realm.write {
                        let myLibrary = SyncControllerSpec.realm.objects(RLibrary.self).first
                        let item = RItem()
                        item.key = itemToDelete
                        item.title = "Delete me"
                        item.library = myLibrary
                        realm.add(item)
                    }

                    let toBeDeletedItem = realm.objects(RItem.self)
                                               .filter("key = %@ AND library.identifier = %d", itemToDelete,
                                                                                               RLibrary.myLibraryId)
                                               .first
                    expect(toBeDeletedItem).toNot(beNil())

                    objects.forEach { object in
                        self.createStub(for: VersionsRequest<String>(libraryType: library, objectType: object, version: 0),
                                        baseUrl: baseUrl, headers: header,
                                        response: [:])
                    }
                    self.createStub(for: SettingsRequest(libraryType: library, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    response: ["tagColors" : ["value": [], "version": 2]])
                    self.createStub(for: DeletionsRequest(libraryType: library, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    response: ["collections": [], "searches": [], "items": [itemToDelete], "tags": []])

                    self.controller = SyncController(userId: SyncControllerSpec.userId,
                                                     handler: SyncControllerSpec.syncHandler)

                    waitUntil(timeout: 10) { doneAction in
                        self.controller?.reportFinish = { _ in
                            let realm = try! Realm(configuration: SyncControllerSpec.realmConfig)
                            realm.refresh()

                            let deletedItem = realm.objects(RItem.self)
                                                   .filter("key = %@ AND library.identifier = %d", itemToDelete,
                                                                                                   RLibrary.myLibraryId)
                                                   .first
                            expect(deletedItem).to(beNil())

                            doneAction()
                        }

                        self.controller?.start()
                    }
                })

                it("should handle new remote item referencing locally missing collection", closure: {
                    let header = ["Last-Modified-Version" : "3"]
                    let library = SyncLibraryType.user(SyncControllerSpec.userId)
                    let objects = SyncObjectType.allCases
                    let itemKey = "AAAAAAAA"
                    let collectionKey = "CCCCCCCC"
                    let itemResponse = [["key": itemKey,
                                         "version": 3,
                                         "library": ["id": 0, "type": "user", "name": "A"],
                                         "data": ["title": "A", "itemType": "thesis", "collections": [collectionKey]]]]

                    let realm = SyncControllerSpec.realm
                    let collection = realm.objects(RItem.self).filter("key = %@", collectionKey).first
                    expect(collection).to(beNil())

                    objects.forEach { object in
                        if object == .item {
                            self.createStub(for: VersionsRequest<String>(libraryType: library, objectType: object, version: 0),
                                            baseUrl: baseUrl, headers: header,
                                            response: [itemKey: 3])
                        } else {
                            self.createStub(for: VersionsRequest<String>(libraryType: library, objectType: object, version: 0),
                                            baseUrl: baseUrl, headers: header,
                                            response: [:])
                        }
                    }
                    self.createStub(for: ObjectsRequest(libraryType: library, objectType: .item, keys: itemKey),
                                    baseUrl: baseUrl, headers: header, response: itemResponse)
                    self.createStub(for: SettingsRequest(libraryType: library, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    response: ["tagColors" : ["value": [], "version": 2]])
                    self.createStub(for: DeletionsRequest(libraryType: library, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    response: ["collections": [], "searches": [], "items": [], "tags": []])

                    self.controller = SyncController(userId: SyncControllerSpec.userId,
                                                     handler: SyncControllerSpec.syncHandler)

                    waitUntil(timeout: 10) { doneAction in
                        self.controller?.reportFinish = { _ in
                            let realm = try! Realm(configuration: SyncControllerSpec.realmConfig)
                            realm.refresh()

                            let item = realm.objects(RItem.self)
                                            .filter("library.identifier = %d AND key = %@", RLibrary.myLibraryId, itemKey)
                                            .first
                            expect(item).toNot(beNil())
                            expect(item?.needsSync).to(beFalse())
                            expect(item?.collections.count).to(equal(1))

                            let collection = item?.collections.first
                            expect(collection).toNot(beNil())
                            expect(collection?.key).to(equal(collectionKey))
                            expect(collection?.needsSync).to(beTrue())

                            doneAction()
                        }

                        self.controller?.start()
                    }
                })

                it("should include unsynced objects in sync queue", closure: {
                    let header = ["Last-Modified-Version" : "3"]
                    let library = SyncLibraryType.user(SyncControllerSpec.userId)
                    let objects = SyncObjectType.allCases
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

                    let realm = SyncControllerSpec.realm
                    try! realm.write {
                        let library = realm.object(ofType: RLibrary.self, forPrimaryKey: RLibrary.myLibraryId)
                        let item = RItem()
                        item.key = unsyncedItemKey
                        item.needsSync = true
                        item.library = library
                        realm.add(item)
                    }

                    let unsynced = realm.objects(RItem.self)
                                        .filter("library.identifier = %d AND key = %@", RLibrary.myLibraryId,
                                                                                        unsyncedItemKey).first
                    expect(unsynced).toNot(beNil())
                    expect(unsynced?.needsSync).to(beTrue())

                    objects.forEach { object in
                        if object == .item {
                            self.createStub(for: VersionsRequest<String>(libraryType: library, objectType: object, version: 0),
                                            baseUrl: baseUrl, headers: header,
                                            response: [responseItemKey: 3])
                        } else {
                            self.createStub(for: VersionsRequest<String>(libraryType: library, objectType: object, version: 0),
                                            baseUrl: baseUrl, headers: header,
                                            response: [:])
                        }
                    }
                    self.createStub(for: ObjectsRequest(libraryType: library, objectType: .item,
                                                        keys: "\(unsyncedItemKey),\(responseItemKey)"),
                                    baseUrl: baseUrl, headers: header, response: itemResponse)
                    self.createStub(for: ObjectsRequest(libraryType: library, objectType: .item,
                                                        keys: "\(responseItemKey),\(unsyncedItemKey)"),
                                    baseUrl: baseUrl, headers: header, response: itemResponse)
                    self.createStub(for: SettingsRequest(libraryType: library, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    response: ["tagColors" : ["value": [], "version": 2]])
                    self.createStub(for: DeletionsRequest(libraryType: library, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    response: ["collections": [], "searches": [], "items": [], "tags": []])

                    self.controller = SyncController(userId: SyncControllerSpec.userId,
                                                     handler: SyncControllerSpec.syncHandler)

                    waitUntil(timeout: 10) { doneAction in
                        self.controller?.reportFinish = { result in
                            let realm = try! Realm(configuration: SyncControllerSpec.realmConfig)
                            realm.refresh()

                            switch result {
                            case .success(let data):
                                let actions = data.0
                                let itemAction = actions.filter({ action -> Bool in
                                    switch action {
                                    case .syncBatchToFile(let batch):
                                        guard batch.object == .item,
                                              let strKeys = batch.keys as? [String] else { return false }
                                        return strKeys.contains(unsyncedItemKey) && strKeys.contains(responseItemKey)
                                    default:
                                        return false
                                    }
                                }).first
                                expect(itemAction).toNot(beNil())
                            case .failure:
                                fail("Sync aborted")
                            }

                            let newItem = realm.objects(RItem.self)
                                               .filter("library.identifier = %d AND key = %@", RLibrary.myLibraryId,
                                                                                               responseItemKey).first
                            expect(newItem).toNot(beNil())
                            expect(newItem?.title).to(equal("A"))

                            let oldItem = realm.objects(RItem.self)
                                               .filter("library.identifier = %d AND key = %@", RLibrary.myLibraryId,
                                                                                               unsyncedItemKey).first
                            expect(oldItem).toNot(beNil())
                            expect(oldItem?.title).to(equal("B"))
                            expect(oldItem?.needsSync).to(beFalse())

                            doneAction()
                        }

                        self.controller?.start()
                    }
                })

                it("should mark object as needsSync if not parsed correctly", closure: {
                    let header = ["Last-Modified-Version" : "3"]
                    let library = SyncLibraryType.user(SyncControllerSpec.userId)
                    let objects = SyncObjectType.allCases
                    let correctKey = "AAAAAAAA"
                    let incorrectKey = "BBBBBBBB"
                    let itemResponse = [["key": correctKey,
                                         "version": 3,
                                         "library": ["id": 0, "type": "user", "name": "A"],
                                         "data": ["title": "A", "itemType": "thesis"]],
                                        ["key": incorrectKey,
                                         "version": 3,
                                         "data": ["title": "A", "itemType": "thesis"]]]

                    objects.forEach { object in
                        if object == .item {
                            self.createStub(for: VersionsRequest<String>(libraryType: library, objectType: object, version: 0),
                                            baseUrl: baseUrl, headers: header,
                                            response: [correctKey: 3, incorrectKey: 3])
                        } else {
                            self.createStub(for: VersionsRequest<String>(libraryType: library, objectType: object, version: 0),
                                            baseUrl: baseUrl, headers: header,
                                            response: [:])
                        }
                    }
                    self.createStub(for: ObjectsRequest(libraryType: library, objectType: .item,
                                                        keys: "\(correctKey),\(incorrectKey)"),
                                    baseUrl: baseUrl, headers: header, response: itemResponse)
                    self.createStub(for: ObjectsRequest(libraryType: library, objectType: .item,
                                                        keys: "\(incorrectKey),\(correctKey)"),
                                    baseUrl: baseUrl, headers: header, response: itemResponse)
                    self.createStub(for: SettingsRequest(libraryType: library, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    response: ["tagColors" : ["value": [], "version": 2]])
                    self.createStub(for: DeletionsRequest(libraryType: library, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    response: ["collections": [], "searches": [], "items": [], "tags": []])

                    self.controller = SyncController(userId: SyncControllerSpec.userId,
                                                     handler: SyncControllerSpec.syncHandler)

                    waitUntil(timeout: 100) { doneAction in
                        self.controller?.reportFinish = { result in
                            let realm = try! Realm(configuration: SyncControllerSpec.realmConfig)
                            realm.refresh()

                            switch result {
                            case .success(let data):
                                expect(data.1.count).to(equal(1))
                            case .failure:
                                fail("Sync aborted")
                            }

                            let correctItem = realm.objects(RItem.self)
                                                   .filter("library.identifier = %d AND key = %@", RLibrary.myLibraryId, correctKey)
                                                   .first
                            expect(correctItem).toNot(beNil())
                            expect(correctItem?.needsSync).to(beFalse())

                            let incorrectItem = realm.objects(RItem.self)
                                                     .filter("library.identifier = %d AND key = %@", RLibrary.myLibraryId, incorrectKey)
                                                     .first
                            expect(incorrectItem).toNot(beNil())
                            expect(incorrectItem?.needsSync).to(beTrue())

                            doneAction()
                        }

                        self.controller?.start()
                    }
                })
            }
        }
    }

    private func createNoChangeStubs(for library: SyncLibraryType, baseUrl: URL, headers: [String: Any]? = nil) {
        let objects = SyncObjectType.allCases
        objects.forEach { object in
            self.createStub(for: VersionsRequest<String>(libraryType: library, objectType: object, version: 0),
                            baseUrl: baseUrl, headers: headers,
                            response: [:])
        }
        self.createStub(for: SettingsRequest(libraryType: library, version: 0),
                        baseUrl: baseUrl, headers: headers,
                        response: ["tagColors" : ["value": [], "version": 2]])
        self.createStub(for: DeletionsRequest(libraryType: library, version: 0),
                        baseUrl: baseUrl, headers: headers,
                        response: ["collections": [], "searches": [], "items": [], "tags": []])
    }

    private func createStub(for request: ApiRequest, baseUrl: URL, headers: [String: Any]? = nil,
                            statusCode: Int32 = 200, response: Any) {
        stub(condition: request.stubCondition(with: baseUrl), response: { _ -> OHHTTPStubsResponse in
            return OHHTTPStubsResponse(jsonObject: response, statusCode: statusCode, headers: headers)
        })
    }

    private func performActionsTest(queue: [QueueAction], result: @escaping (TestAction) -> Single<()>,
                                    check: @escaping ([QueueAction]) -> Void) -> SyncController {
        let handler = TestHandler()
        let controller = SyncController(userId: SyncControllerSpec.userId, handler: handler)

        handler.requestResult = result

        controller.start(with: queue, finishedAction: { result in
            switch result {
            case .success(let data):
                check(data.0)
            case .failure: break
            }
        })

        return controller
    }

    private func performErrorTest(queue: [QueueAction], result: @escaping (TestAction) -> Single<()>,
                                  check: @escaping (Error) -> Void) -> SyncController {
        let handler = TestHandler()
        let controller = SyncController(userId: SyncControllerSpec.userId, handler: handler)

        handler.requestResult = result

        controller.start(with: queue, finishedAction: { result in
            switch result {
            case .success: break
            case .failure(let error):
                check(error)
            }
        })

        return controller
    }
}

fileprivate struct TestErrors {
    static let nonFatal = SyncActionHandlerError.expired
    static let versionMismatch = SyncActionHandlerError.versionMismatch
    static let fatal = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: nil)
    static let file = NSError(domain: "file", code: 123, userInfo: nil)
}

fileprivate enum TestAction {
    case loadGroups
    case syncVersions(SyncObjectType)
    case downloadObject(SyncObjectType)
    case storeObject(SyncObjectType)
    case resync(SyncObjectType)
    case storeVersion(SyncLibraryType)
    case markResync(SyncObjectType)
    case syncDeletions(SyncLibraryType)
    case syncSettings(SyncLibraryType)
}

fileprivate class TestHandler: SyncActionHandler {
    var requestResult: ((TestAction) -> Single<()>)?

    private func result(for action: TestAction) -> Single<()> {
        return self.requestResult?(action) ?? Single.just(())
    }

    func loadAllLibraryIdsAndVersions() -> PrimitiveSequence<SingleTrait, Array<(Int, String, Versions)>> {
        return self.result(for: .loadGroups).flatMap {
            return Single.just([(SyncControllerSpec.groupId, "", SyncControllerSpec.groupIdVersions)])
        }
    }

    func synchronizeVersions(for library: SyncLibraryType, object: SyncObjectType, since sinceVersion: Int?,
                             current currentVersion: Int?, syncAll: Bool) -> Single<(Int, Array<Any>)> {
        return self.result(for: .syncVersions(object)).flatMap {
            let data = SyncControllerSpec.syncVersionData
            switch object {
            case .group:
                return Single.just((data.0, Array(0..<data.1)))
            default:
                return Single.just((data.0, (0..<data.1).map({ $0.description })))
            }
        }
    }

    func downloadObjectJson(for keys: String, library: SyncLibraryType,
                            object: SyncObjectType, version: Int, index: Int) -> Completable {
        return self.result(for: .downloadObject(object)).asCompletable()
    }

    func markForResync(keys: [Any], library: SyncLibraryType, object: SyncObjectType) -> Completable {
        return self.result(for: .markResync(object)).asCompletable()
    }

    func synchronizeDbWithFetchedFiles(library: SyncLibraryType, object: SyncObjectType,
                                       version: Int, index: Int) -> Single<([String], [Error])> {
        let keys = SyncControllerSpec.expectedKeys
        return self.result(for: .storeObject(object)).flatMap({ return Single.just((keys, [])) })
    }

    func storeVersion(_ version: Int, for library: SyncLibraryType, type: UpdateVersionType) -> Completable {
        return self.result(for: .storeVersion(.group(SyncControllerSpec.groupId))).asCompletable()
    }

    func synchronizeDeletions(for library: SyncLibraryType, since sinceVersion: Int,
                              current currentVersion: Int?) -> Completable {
        return self.result(for: .syncDeletions(library)).asCompletable()
    }

    func synchronizeSettings(for library: SyncLibraryType, current currentVersion: Int?,
                             since version: Int?) -> Single<(Bool, Int)> {
        return self.result(for: .syncSettings(library)).flatMap {
            let data = SyncControllerSpec.syncVersionData
            return Single.just((true, data.0))
        }
    }

}

fileprivate class TestFileStorage: FileStorage {
    private var data: Data?
    private var file: File?

    func read(_ file: File) throws -> Data {
        if file.createUrl() == self.file?.createUrl(), let data = self.data {
            return data
        }
        throw TestErrors.file
    }

    func write(_ data: Data, to file: File, options: Data.WritingOptions) throws {
        self.data = data
        self.file = file
    }

    func remove(_ file: File) throws {
        if file.createUrl() == self.file?.createUrl() {
            self.data = nil
            self.file = nil
        }
    }

    func has(_ file: File) -> Bool {
        return file.createUrl() == self.file?.createUrl()
    }

    func createDictionaries(for file: File) throws {}
}
