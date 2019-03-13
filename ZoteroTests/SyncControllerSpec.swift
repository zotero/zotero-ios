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
    private static let emptyUpdateDataSource = TestDataSource(batches: [])

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
                    let initial: [SyncController.Action] = [.storeVersion(3, .group(SyncControllerSpec.groupId), .collection)]
                    let expected: [SyncController.Action] = initial
                    var all: [SyncController.Action]?

                    self.controller = self.performActionsTest(queue: initial,
                                                              libraries: .all,
                                                              result: { _ in
                                                                  return Single.just(())
                                                              }, check: { result in
                                                                  all = result
                                                              })

                    expect(all).toEventually(equal(expected))
                }

                it("processes sync batch to db") {
                    let action = SyncController.DownloadBatch(library: .user(SyncControllerSpec.userId),
                                             object: .group, keys: [1], version: 0)
                    let initial: [SyncController.Action] = [.syncBatchToDb(action)]
                    let expected: [SyncController.Action] = initial
                    var all: [SyncController.Action]?

                    self.controller = self.performActionsTest(queue: initial,
                                                              libraries: .all,
                                                              result: { _ in
                                                                  return Single.just(())
                                                              }, check: { result in
                                                                  all = result
                                                              })

                    expect(all).toEventually(equal(expected))
                }

                it("processes sync versions (collection) action") {
                    SyncControllerSpec.syncVersionData = (3, 35)

                    let library = SyncController.Library.user(SyncControllerSpec.userId)
                    let keys1 = (0..<5).map({ $0.description })
                    let keys2 = (5..<15).map({ $0.description })
                    let keys3 = (15..<35).map({ $0.description })
                    let initial: [SyncController.Action] = [.syncVersions(.user(SyncControllerSpec.userId), .collection, 2)]
                    let expected: [SyncController.Action] = [.syncVersions(.user(SyncControllerSpec.userId), .collection, 2),
                                                   .syncBatchToDb(SyncController.DownloadBatch(library: library,
                                                                              object: .collection,
                                                                              keys: keys1,
                                                                              version: 3)),
                                                   .syncBatchToDb(SyncController.DownloadBatch(library: library,
                                                                              object: .collection,
                                                                              keys: keys2,
                                                                              version: 3)),
                                                   .syncBatchToDb(SyncController.DownloadBatch(library: library,
                                                                              object: .collection,
                                                                              keys: keys3,
                                                                              version: 3)),
                                                   .storeVersion(3, .user(SyncControllerSpec.userId), .collection)]
                    var all: [SyncController.Action]?

                    self.controller = self.performActionsTest(queue: initial,
                                                              libraries: .all,
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
                    let initial: [SyncController.Action] = [.createLibraryActions(.all, false)]
                    let expected: [SyncController.Action] = [.createLibraryActions(.all, false),
                                                   .syncSettings(.group(groupId), 1),
                                                   .storeSettingsVersion(3, .group(groupId)),
                                                   .syncVersions(.group(groupId), .collection, 2),
                                                   .syncBatchToDb(SyncController.DownloadBatch(library: .group(groupId),
                                                                                object: .collection,
                                                                                keys: ["0"],
                                                                                version: 3)),
                                                   .storeVersion(3, .group(groupId), .collection),
                                                   .syncVersions(.group(groupId), .search, 1),
                                                   .syncBatchToDb(SyncController.DownloadBatch(library: .group(groupId),
                                                                              object: .search,
                                                                              keys: ["0"],
                                                                              version: 3)),
                                                   .storeVersion(3, .group(groupId), .search),
                                                   .syncVersions(.group(groupId), .item, 1),
                                                   .syncBatchToDb(SyncController.DownloadBatch(library: .group(groupId),
                                                                                object: .item,
                                                                                keys: ["0"],
                                                                                version: 3)),
                                                   .storeVersion(3, .group(groupId), .item),
                                                   .syncVersions(.group(groupId), .trash, 1),
                                                   .syncBatchToDb(SyncController.DownloadBatch(library: .group(groupId),
                                                                                object: .trash,
                                                                                keys: ["0"],
                                                                                version: 3)),
                                                   .storeVersion(3, .group(groupId), .trash),
                                                   .syncDeletions(.group(groupId), 1)]
                    var all: [SyncController.Action]?

                    self.controller = self.performActionsTest(queue: initial,
                                                              libraries: .all,
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
                    let initial: [SyncController.Action] = [.syncVersions(.user(SyncControllerSpec.userId), .group, nil)]
                    let expected: [SyncController.Action] = [.syncVersions(.user(SyncControllerSpec.userId), .group, nil),
                                                   .syncBatchToDb(SyncController.DownloadBatch(library: .user(SyncControllerSpec.userId),
                                                                              object: .group,
                                                                              keys: [0],
                                                                              version: 7)),
                                                   .createLibraryActions(.all, false),
                                                   .syncSettings(.group(groupId), 4),
                                                   .storeSettingsVersion(7, .group(groupId)),
                                                   .syncVersions(.group(groupId), .collection, 4),
                                                   .syncBatchToDb(SyncController.DownloadBatch(library: .group(groupId),
                                                                              object: .collection,
                                                                              keys: ["0"],
                                                                              version: 7)),
                                                   .storeVersion(7, .group(groupId), .collection),
                                                   .syncVersions(.group(groupId), .search, 2),
                                                   .syncBatchToDb(SyncController.DownloadBatch(library: .group(groupId),
                                                                              object: .search,
                                                                              keys: ["0"],
                                                                              version: 7)),
                                                   .storeVersion(7, .group(groupId), .search),
                                                   .syncVersions(.group(groupId), .item, 4),
                                                   .syncBatchToDb(SyncController.DownloadBatch(library: .group(groupId),
                                                                              object: .item,
                                                                              keys: ["0"],
                                                                              version: 7)),
                                                   .storeVersion(7, .group(groupId), .item),
                                                   .syncVersions(.group(groupId), .trash, 2),
                                                   .syncBatchToDb(SyncController.DownloadBatch(library: .group(groupId),
                                                                              object: .trash,
                                                                              keys: ["0"],
                                                                              version: 7)),
                                                   .storeVersion(7, .group(groupId), .trash),
                                                   .syncDeletions(.group(groupId), 4)]
                    var all: [SyncController.Action]?

                    self.controller = self.performActionsTest(queue: initial,
                                                              libraries: .all,
                                                              result: { _ in
                                                                  return Single.just(())
                                                              }, check: { result in
                                                                  all = result
                                                              })

                    expect(all).toEventually(equal(expected))
                }

                it("processes specific library only") {
                    SyncControllerSpec.syncVersionData = (7, 5)
                    SyncControllerSpec.groupIdVersions = Versions(collections: 4, items: 4, trash: 2, searches: 2,
                                                                  deletions: 4, settings: 4)

                    let groupId = 2
                    let keys = ["0", "1", "2", "3", "4"]
                    let initial: [SyncController.Action] = [.syncVersions(.user(SyncControllerSpec.userId), .group, nil)]
                    let expected: [SyncController.Action] = [.syncVersions(.user(SyncControllerSpec.userId), .group, nil),
                                                             .syncBatchToDb(SyncController.DownloadBatch(library: .user(SyncControllerSpec.userId),
                                                                                                 object: .group,
                                                                                                 keys: [2],
                                                                                                 version: 7)),
                                                             .createLibraryActions(.specific([groupId]), false),
                                                             .syncSettings(.group(groupId), 4),
                                                             .storeSettingsVersion(7, .group(groupId)),
                                                             .syncVersions(.group(groupId), .collection, 4),
                                                             .syncBatchToDb(SyncController.DownloadBatch(library: .group(groupId),
                                                                                                 object: .collection,
                                                                                                 keys: keys,
                                                                                                 version: 7)),
                                                             .storeVersion(7, .group(groupId), .collection),
                                                             .syncVersions(.group(groupId), .search, 2),
                                                             .syncBatchToDb(SyncController.DownloadBatch(library: .group(groupId),
                                                                                                 object: .search,
                                                                                                 keys: keys,
                                                                                                 version: 7)),
                                                             .storeVersion(7, .group(groupId), .search),
                                                             .syncVersions(.group(groupId), .item, 4),
                                                             .syncBatchToDb(SyncController.DownloadBatch(library: .group(groupId),
                                                                                                 object: .item,
                                                                                                 keys: keys,
                                                                                                 version: 7)),
                                                             .storeVersion(7, .group(groupId), .item),
                                                             .syncVersions(.group(groupId), .trash, 2),
                                                             .syncBatchToDb(SyncController.DownloadBatch(library: .group(groupId),
                                                                                                 object: .trash,
                                                                                                 keys: keys,
                                                                                                 version: 7)),
                                                             .storeVersion(7, .group(groupId), .trash),
                                                             .syncDeletions(.group(groupId), 4)]
                    var all: [SyncController.Action]?

                    self.controller = self.performActionsTest(queue: initial,
                                                              libraries: .specific([groupId]),
                                                              result: { action in
                                                                  return Single.just(())
                                                              }, check: { result in
                                                                  all = result
                                                              })

                    expect(all).toEventually(equal(expected))
                }

                it("doesn't process group metadata when only my library is supposed to sync") {
                    var all: [SyncController.Action]?

                    self.controller = self.performActionsTest(libraries: .specific([RLibrary.myLibraryId]),
                                                              updates: [],
                                                              result: { _ -> Single<()> in
                                                                  return Single.just(())
                                                              }, check: { actions in
                                                                  all = actions
                                                              })
                    self.controller?.start(type: .normal, libraries: .specific([RLibrary.myLibraryId]))

                    expect(all?.first).toEventually(equal(.createLibraryActions(.specific([RLibrary.myLibraryId]), false)))
                }

                it("processes update actions") {
                    let library: SyncController.Library = .user(SyncControllerSpec.userId)
                    let batch1 = SyncController.WriteBatch(library: library,
                                                           object: .collection,
                                                           version: 1,
                                                           parameters: [["name": "A",
                                                                         "key": "AAAAAAAA",
                                                                         "version": 1]])
                    let batch2 = SyncController.WriteBatch(library: library,
                                                           object: .item,
                                                           version: 2,
                                                           parameters: [["title": "B",
                                                                         "key": "BBBBBBBB",
                                                                         "version": 2]])
                    var all: [SyncController.Action]?
                    let expected: [SyncController.Action] = [.createLibraryActions(.specific([RLibrary.myLibraryId]), false),
                                                             .submitWriteBatch(batch1),
                                                             .submitWriteBatch(batch2)]

                    self.controller = self.performActionsTest(libraries: .specific([RLibrary.myLibraryId]),
                                                              updates: [batch1, batch2],
                                                              result: { _ -> Single<()> in
                                                                  return Single.just(())
                                                              }, check: { actions in
                                                                  all = actions
                                                              })
                    self.controller?.start(type: .normal, libraries: .specific([RLibrary.myLibraryId]))

                    expect(all).toEventually(equal(expected))
                }

                it("updates local data from remote when update returns 412") {
                    SyncControllerSpec.syncVersionData = (3, 1)
                    SyncControllerSpec.groupIdVersions = Versions(collections: 2, items: 2, trash: 2, searches: 2,
                                                                  deletions: 2, settings: 2)

                    let library: SyncController.Library = .user(SyncControllerSpec.userId)
                    let batch1 = SyncController.WriteBatch(library: library,
                                                           object: .collection,
                                                           version: 1,
                                                           parameters: [["name": "A",
                                                                         "key": "AAAAAAAA",
                                                                         "version": 1]])
                    var all: [SyncController.Action]?
                    let expected: [SyncController.Action] = [.createLibraryActions(.specific([RLibrary.myLibraryId]), false),
                                                             .submitWriteBatch(batch1),
                                                             .createLibraryActions(.specific([RLibrary.myLibraryId]), true),
                                                             .syncSettings(library, 2),
                                                             .storeSettingsVersion(3, library),
                                                             .syncVersions(library, .collection, 2),
                                                             .syncBatchToDb(SyncController.DownloadBatch(library: library,
                                                                                                         object: .collection,
                                                                                                         keys: ["0"],
                                                                                                         version: 3)),
                                                             .storeVersion(3, library, .collection),
                                                             .syncVersions(library, .search, 2),
                                                             .syncBatchToDb(SyncController.DownloadBatch(library: library,
                                                                                                         object: .search,
                                                                                                         keys: ["0"],
                                                                                                         version: 3)),
                                                             .storeVersion(3, library, .search),
                                                             .syncVersions(library, .item, 2),
                                                             .syncBatchToDb(SyncController.DownloadBatch(library: library,
                                                                                                         object: .item,
                                                                                                         keys: ["0"],
                                                                                                         version: 3)),
                                                             .storeVersion(3, library, .item),
                                                             .syncVersions(library, .trash, 2),
                                                             .syncBatchToDb(SyncController.DownloadBatch(library: library,
                                                                                                         object: .trash,
                                                                                                         keys: ["0"],
                                                                                                         version: 3)),
                                                             .storeVersion(3, library, .trash),
                                                             .syncDeletions(library, 2),
                                                             .submitWriteBatch(batch1)]
                    var updateCount = 0

                    let preconditionError = AFError.responseValidationFailed(reason: .unacceptableStatusCode(code: 412))

                    self.controller = self.performActionsTest(libraries: .specific([RLibrary.myLibraryId]),
                                                              updates: [batch1],
                                                              result: { action -> Single<()> in
                                                                  switch action {
                                                                  case .submitUpdate:
                                                                      if updateCount == 0 {
                                                                          updateCount += 1
                                                                          return Single.error(preconditionError)
                                                                      }
                                                                  default: break
                                                                  }
                                                                  return Single.just(())
                                                              }, check: { actions in
                                                                  all = actions
                                                              })
                    self.controller?.start(type: .normal, libraries: .specific([RLibrary.myLibraryId]))

                    expect(all).toEventually(equal(expected))
                }
            }

            describe("fatal error handling") {
                it("doesn't process store version action") {
                    let initial: [SyncController.Action] = [.storeVersion(1, .user(SyncControllerSpec.userId), .group)]
                    var error: Zotero.SyncError?

                    self.controller = self.performErrorTest(queue: initial,
                                                            libraries: .all,
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

                it("doesn't process sync batch to db") {
                    let action = SyncController.DownloadBatch(library: .user(SyncControllerSpec.userId), object: .group,
                                             keys: [1], version: 0)
                    let initial: [SyncController.Action] = [.syncBatchToDb(action)]
                    var error: Zotero.SyncError?

                    self.controller = self.performErrorTest(queue: initial,
                                                            libraries: .all,
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

                    let initial: [SyncController.Action] = [.syncVersions(.user(SyncControllerSpec.userId), .collection, 1)]
                    var error: Zotero.SyncError?

                    self.controller = self.performErrorTest(queue: initial,
                                                            libraries: .all,
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

                    let initial: [SyncController.Action] = [.createLibraryActions(.all, false)]
                    var error: Zotero.SyncError?

                    self.controller = self.performErrorTest(queue: initial,
                                                            libraries: .all,
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

                    let initial: [SyncController.Action] = [.syncVersions(.user(SyncControllerSpec.userId), .group, nil)]
                    var didFinish: Bool?

                    self.controller = self.performActionsTest(queue: initial,
                                                              libraries: .all,
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
                    let library = SyncController.Library.user(SyncControllerSpec.userId)
                    let objects = SyncController.Object.allCases

                    var versionResponses: [SyncController.Object: Any] = [:]
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

                    let objectKeys: [SyncController.Object: String] = [.collection: "AAAAAAAA",
                                                                .search: "AAAAAAAA",
                                                                .item: "AAAAAAAA",
                                                                .trash: "BBBBBBBB"]
                    var objectResponses: [SyncController.Object: Any] = [:]
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
                                                     handler: SyncControllerSpec.syncHandler,
                                                     updateDataSource: SyncControllerSpec.emptyUpdateDataSource)

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

                        self.controller?.start(type: .normal, libraries: .all)
                    }
                })

                it("should download items into a new read-only group", closure: {
                    let header = ["Last-Modified-Version" : "3"]
                    let groupId = 123
                    let library = SyncController.Library.group(groupId)
                    let objects = SyncController.Object.allCases

                    var versionResponses: [SyncController.Object: Any] = [:]
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

                    let objectKeys: [SyncController.Object: String] = [.collection: "AAAAAAAA",
                                                                .search: "AAAAAAAA",
                                                                .item: "AAAAAAAA",
                                                                .trash: "BBBBBBBB",
                                                                .group: groupId.description]
                    var objectResponses: [SyncController.Object: Any] = [:]
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

                    let myLibrary = SyncController.Library.user(SyncControllerSpec.userId)
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
                                                     handler: SyncControllerSpec.syncHandler,
                                                     updateDataSource: SyncControllerSpec.emptyUpdateDataSource)

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

                        self.controller?.start(type: .normal, libraries: .all)
                    }
                })

                it("should apply remote deletions", closure: {
                    let header = ["Last-Modified-Version" : "3"]
                    let library = SyncController.Library.user(SyncControllerSpec.userId)
                    let itemToDelete = "CCCCCCCC"
                    let objects = SyncController.Object.allCases

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
                                                     handler: SyncControllerSpec.syncHandler,
                                                     updateDataSource: SyncControllerSpec.emptyUpdateDataSource)

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

                        self.controller?.start(type: .normal, libraries: .all)
                    }
                })

                it("should handle new remote item referencing locally missing collection", closure: {
                    let header = ["Last-Modified-Version" : "3"]
                    let library = SyncController.Library.user(SyncControllerSpec.userId)
                    let objects = SyncController.Object.allCases
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
                                                     handler: SyncControllerSpec.syncHandler,
                                                     updateDataSource: SyncControllerSpec.emptyUpdateDataSource)

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

                        self.controller?.start(type: .normal, libraries: .all)
                    }
                })

                it("should include unsynced objects in sync queue", closure: {
                    let header = ["Last-Modified-Version" : "3"]
                    let library = SyncController.Library.user(SyncControllerSpec.userId)
                    let objects = SyncController.Object.allCases
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
                                                     handler: SyncControllerSpec.syncHandler,
                                                     updateDataSource: SyncControllerSpec.emptyUpdateDataSource)

                    waitUntil(timeout: 10) { doneAction in
                        self.controller?.reportFinish = { result in
                            let realm = try! Realm(configuration: SyncControllerSpec.realmConfig)
                            realm.refresh()

                            switch result {
                            case .success(let data):
                                let actions = data.0
                                let itemAction = actions.filter({ action -> Bool in
                                    switch action {
                                    case .syncBatchToDb(let batch):
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

                        self.controller?.start(type: .normal, libraries: .all)
                    }
                })

                it("should mark object as needsSync if not parsed correctly", closure: {
                    let header = ["Last-Modified-Version" : "3"]
                    let library = SyncController.Library.user(SyncControllerSpec.userId)
                    let objects = SyncController.Object.allCases
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
                                                     handler: SyncControllerSpec.syncHandler,
                                                     updateDataSource: SyncControllerSpec.emptyUpdateDataSource)

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

                        self.controller?.start(type: .normal, libraries: .all)
                    }
                })
            }
        }
    }

    private func createNoChangeStubs(for library: SyncController.Library, baseUrl: URL, headers: [String: Any]? = nil) {
        let objects = SyncController.Object.allCases
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

    private func performActionsTest(queue: [SyncController.Action], libraries: SyncController.LibrarySyncType,
                                    result: @escaping (TestAction) -> Single<()>,
                                    check: @escaping ([SyncController.Action]) -> Void) -> SyncController {
        let handler = TestHandler()
        let controller = SyncController(userId: SyncControllerSpec.userId, handler: handler,
                                        updateDataSource: SyncControllerSpec.emptyUpdateDataSource)

        handler.requestResult = result

        controller.start(with: queue, libraries: libraries, finishedAction: { result in
            switch result {
            case .success(let data):
                check(data.0)
            case .failure: break
            }
        })

        return controller
    }

    private func performActionsTest(libraries: SyncController.LibrarySyncType, updates: [SyncController.WriteBatch],
                                    result: @escaping (TestAction) -> Single<()>,
                                    check: @escaping ([SyncController.Action]) -> Void) -> SyncController {
        let handler = TestHandler()
        let dataSource = TestDataSource(batches: updates)
        let controller = SyncController(userId: SyncControllerSpec.userId,
                                        handler: handler, updateDataSource: dataSource)

        handler.requestResult = result
        controller.reportFinish = { result in
            switch result {
            case .success(let data):
                check(data.0)
            case .failure: break
            }
        }

        return controller
    }

    private func performErrorTest(queue: [SyncController.Action], libraries: SyncController.LibrarySyncType,
                                  result: @escaping (TestAction) -> Single<()>,
                                  check: @escaping (Error) -> Void) -> SyncController {
        let handler = TestHandler()
        let controller = SyncController(userId: SyncControllerSpec.userId, handler: handler,
                                        updateDataSource: SyncControllerSpec.emptyUpdateDataSource)

        handler.requestResult = result

        controller.start(with: queue, libraries: libraries, finishedAction: { result in
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
    case loadSpecificGroups([Int])
    case syncVersions(SyncController.Object)
    case storeObject(SyncController.Object)
    case resync(SyncController.Object)
    case storeVersion(SyncController.Library)
    case markResync(SyncController.Object)
    case syncDeletions(SyncController.Library)
    case syncSettings(SyncController.Library)
    case submitUpdate(SyncController.Library, SyncController.Object)
}

fileprivate class TestHandler: SyncActionHandler {
    var requestResult: ((TestAction) -> Single<()>)?

    private func result(for action: TestAction) -> Single<()> {
        return self.requestResult?(action) ?? Single.just(())
    }

    func loadAllLibraryData() -> Single<[(Int, String, Versions)]> {
        return self.result(for: .loadGroups).flatMap {
            return Single.just([(SyncControllerSpec.groupId, "", SyncControllerSpec.groupIdVersions)])
        }
    }

    func loadLibraryData(for libraryIds: [Int]) -> Single<[(Int, String, Versions)]> {
        return self.result(for: .loadSpecificGroups(libraryIds)).flatMap { _ in
            return Single.just(libraryIds.map({ ($0, "", SyncControllerSpec.groupIdVersions) }))
        }
    }

    func synchronizeVersions(for library: SyncController.Library, object: SyncController.Object, since sinceVersion: Int?,
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

    func markForResync(keys: [Any], library: SyncController.Library, object: SyncController.Object) -> Completable {
        return self.result(for: .markResync(object)).asCompletable()
    }

    func fetchAndStoreObjects(with keys: [Any], library: SyncController.Library, object: SyncController.Object,
                              version: Int) -> Single<([String], [Error])> {
        let keys = SyncControllerSpec.expectedKeys
        return self.result(for: .storeObject(object)).flatMap({ return Single.just((keys, [])) })
    }

    func storeVersion(_ version: Int, for library: SyncController.Library, type: UpdateVersionType) -> Completable {
        return self.result(for: .storeVersion(.group(SyncControllerSpec.groupId))).asCompletable()
    }

    func synchronizeDeletions(for library: SyncController.Library, since sinceVersion: Int,
                              current currentVersion: Int?) -> Completable {
        return self.result(for: .syncDeletions(library)).asCompletable()
    }

    func synchronizeSettings(for library: SyncController.Library, current currentVersion: Int?,
                             since version: Int?) -> Single<(Bool, Int)> {
        return self.result(for: .syncSettings(library)).flatMap {
            let data = SyncControllerSpec.syncVersionData
            return Single.just((true, data.0))
        }
    }

    func submitUpdate(for library: SyncController.Library, object: SyncController.Object,
                      parameters: [[String : Any]]) -> Completable {
        return Completable.empty()
    }


    func submitUpdate(for library: SyncController.Library, object: SyncController.Object, since version: Int,
                      parameters: [[String : Any]]) -> Single<[String]> {
        return self.result(for: .submitUpdate(library, object)).flatMap {
            return Single.just([])
        }
    }
}

fileprivate class TestDataSource: SyncUpdateDataSource {
    private let batches: [SyncController.WriteBatch]

    init(batches: [SyncController.WriteBatch]) {
        self.batches = batches
    }

    func updates(for library: SyncController.Library, versions: Versions) throws -> [SyncController.WriteBatch] {
        return self.batches
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
