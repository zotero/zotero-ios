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
    private static let conflictDelays = [0, 3, 6, 9]
    private static let apiClient = ZoteroApiClient(baseUrl: ApiConstants.baseUrlString)
    private static var schemaController: SchemaController = {
        let controller = SchemaController(apiClient: apiClient, userDefaults: UserDefaults.standard)
        controller.reloadSchemaIfNeeded()
        return controller
    }()
    private static let userLibrary: SyncController.Library = .user(userId, .myLibrary)
    private static let realmConfig = Realm.Configuration(inMemoryIdentifier: "TestsRealmConfig")
    private static let realm = try! Realm(configuration: realmConfig) // Retain realm with inMemoryIdentifier so that data are not deleted
    private static let syncHandler = SyncActionHandlerController(userId: userId,
                                                                 apiClient: ZoteroApiClient(baseUrl: ApiConstants.baseUrlString),
                                                                 dbStorage: RealmDbStorage(config: realmConfig),
                                                                 fileStorage: TestFileStorage(),
                                                                 schemaController: schemaController,
                                                                 syncDelayIntervals: [2])
    private static let updateDataSource = UpdateDataSource(dbStorage: RealmDbStorage(config: realmConfig))
    private static let emptyUpdateDataSource = TestDataSource(writeBatches: [], deleteBatches: [])

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

                let myLibrary = RCustomLibrary()
                myLibrary.rawType = RCustomLibraryType.myLibrary.rawValue
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
                    let action = SyncController.DownloadBatch(library: SyncControllerSpec.userLibrary,
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

                    let library = SyncControllerSpec.userLibrary
                    let keys1 = (0..<5).map({ $0.description })
                    let keys2 = (5..<15).map({ $0.description })
                    let keys3 = (15..<35).map({ $0.description })
                    let initial: [SyncController.Action] = [.syncVersions(library, .collection, 2)]
                    let expected: [SyncController.Action] = [.syncVersions(library, .collection, 2),
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
                                                             .storeVersion(3, library, .collection)]
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
                    let initial: [SyncController.Action] = [.createLibraryActions(.all, .automatic)]
                    let expected: [SyncController.Action] = [.createLibraryActions(.all, .automatic),
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

                    let userLibrary = SyncControllerSpec.userLibrary
                    let groupLibrary = SyncController.Library.group(SyncControllerSpec.groupId)
                    let initial: [SyncController.Action] = [.syncVersions(userLibrary, .group, nil)]
                    let expected: [SyncController.Action] = [.syncVersions(userLibrary, .group, nil),
                                                             .syncBatchToDb(SyncController.DownloadBatch(library: userLibrary,
                                                                                                         object: .group,
                                                                                                         keys: [0],
                                                                                                         version: 7)),
                                                             .createLibraryActions(.all, .automatic),
                                                             .syncSettings(groupLibrary, 4),
                                                             .storeSettingsVersion(7, groupLibrary),
                                                             .syncVersions(groupLibrary, .collection, 4),
                                                             .syncBatchToDb(SyncController.DownloadBatch(library: groupLibrary,
                                                                                                         object: .collection,
                                                                                                         keys: ["0"],
                                                                                                         version: 7)),
                                                             .storeVersion(7, groupLibrary, .collection),
                                                             .syncVersions(groupLibrary, .search, 2),
                                                             .syncBatchToDb(SyncController.DownloadBatch(library: groupLibrary,
                                                                                                         object: .search,
                                                                                                         keys: ["0"],
                                                                                                         version: 7)),
                                                             .storeVersion(7, groupLibrary, .search),
                                                             .syncVersions(groupLibrary, .item, 4),
                                                             .syncBatchToDb(SyncController.DownloadBatch(library: groupLibrary,
                                                                                                         object: .item,
                                                                                                         keys: ["0"],
                                                                                                         version: 7)),
                                                             .storeVersion(7, groupLibrary, .item),
                                                             .syncVersions(groupLibrary, .trash, 2),
                                                             .syncBatchToDb(SyncController.DownloadBatch(library: groupLibrary,
                                                                                                         object: .trash,
                                                                                                         keys: ["0"],
                                                                                                         version: 7)),
                                                             .storeVersion(7, groupLibrary, .trash),
                                                             .syncDeletions(groupLibrary, 4)]
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
                    let groupLibrary = SyncController.Library.group(groupId)
                    let userLibrary = SyncControllerSpec.userLibrary
                    let keys = ["0", "1", "2", "3", "4"]

                    let initial: [SyncController.Action] = [.loadKeyPermissions, .syncVersions(userLibrary, .group, nil)]
                    let expected: [SyncController.Action] = [.loadKeyPermissions,
                                                             .syncVersions(userLibrary, .group, nil),
                                                             .syncBatchToDb(SyncController.DownloadBatch(library: userLibrary,
                                                                                                         object: .group,
                                                                                                         keys: [2],
                                                                                                         version: 7)),
                                                             .createLibraryActions(.specific([.group(groupId)]), .automatic),
                                                             .syncSettings(groupLibrary, 4),
                                                             .storeSettingsVersion(7, groupLibrary),
                                                             .syncVersions(groupLibrary, .collection, 4),
                                                             .syncBatchToDb(SyncController.DownloadBatch(library: groupLibrary,
                                                                                                         object: .collection,
                                                                                                         keys: keys,
                                                                                                         version: 7)),
                                                             .storeVersion(7, groupLibrary, .collection),
                                                             .syncVersions(groupLibrary, .search, 2),
                                                             .syncBatchToDb(SyncController.DownloadBatch(library: groupLibrary,
                                                                                                         object: .search,
                                                                                                         keys: keys,
                                                                                                         version: 7)),
                                                             .storeVersion(7, groupLibrary, .search),
                                                             .syncVersions(groupLibrary, .item, 4),
                                                             .syncBatchToDb(SyncController.DownloadBatch(library: groupLibrary,
                                                                                                         object: .item,
                                                                                                         keys: keys,
                                                                                                         version: 7)),
                                                             .storeVersion(7, groupLibrary, .item),
                                                             .syncVersions(groupLibrary, .trash, 2),
                                                             .syncBatchToDb(SyncController.DownloadBatch(library: groupLibrary,
                                                                                                         object: .trash,
                                                                                                         keys: keys,
                                                                                                         version: 7)),
                                                             .storeVersion(7, groupLibrary, .trash),
                                                             .syncDeletions(groupLibrary, 4)]
                    var all: [SyncController.Action]?

                    self.controller = self.performActionsTest(queue: initial,
                                                              libraries: .specific([.group(groupId)]),
                                                              result: { action in
                                                                  return Single.just(())
                                                              }, check: { result in
                                                                  all = result
                                                              })

                    expect(all).toEventually(equal(expected))
                }

                it("doesn't process group metadata when only my library is supposed to sync") {
                    var all: [SyncController.Action]?

                    self.controller = self.performActionsTest(libraries: .specific([.custom(.myLibrary)]),
                                                              updates: [],
                                                              result: { _ -> Single<()> in
                                                                  return Single.just(())
                                                              }, check: { actions in
                                                                  all = actions
                                                              })
                    self.controller?.start(type: .normal, libraries: .specific([.custom(.myLibrary)]))

                    expect(all?[1]).toEventually(equal(.createLibraryActions(.specific([.custom(.myLibrary)]), .automatic)))
                }

                it("processes update actions") {
                    SyncControllerSpec.syncVersionData = (4, 0)
                    let library = SyncControllerSpec.userLibrary
                    let batch1 = SyncController.WriteBatch(library: library,
                                                           object: .collection,
                                                           version: 1,
                                                           parameters: [["name": "A",
                                                                         "key": "AAAAAAAA",
                                                                         "version": 1]])
                    let batch2 = SyncController.WriteBatch(library: library,
                                                           object: .item,
                                                           version: 1,
                                                           parameters: [["title": "B",
                                                                         "key": "BBBBBBBB",
                                                                         "version": 2]])
                    let expectedBatch2 = SyncController.WriteBatch(library: library,
                                                                   object: .item,
                                                                   version: 4,
                                                                   parameters: [["title": "B",
                                                                                 "key": "BBBBBBBB",
                                                                                 "version": 2]])

                    var all: [SyncController.Action]?
                    let expected: [SyncController.Action] = [.loadKeyPermissions,
                                                             .createLibraryActions(.specific([.custom(.myLibrary)]), .automatic),
                                                             .submitWriteBatch(batch1),
                                                             .submitWriteBatch(expectedBatch2)]

                    self.controller = self.performActionsTest(libraries: .specific([.custom(.myLibrary)]),
                                                              updates: [batch1, batch2],
                                                              result: { _ -> Single<()> in
                                                                  return Single.just(())
                                                              }, check: { actions in
                                                                  all = actions
                                                              })
                    self.controller?.start(type: .normal, libraries: .specific([.custom(.myLibrary)]))

                    expect(all).toEventually(equal(expected))
                }

                it("updates local data from remote when update returns 412") {
                    SyncControllerSpec.syncVersionData = (3, 1)
                    SyncControllerSpec.groupIdVersions = Versions(collections: 2, items: 2, trash: 2, searches: 2,
                                                                  deletions: 2, settings: 2)

                    let library = SyncControllerSpec.userLibrary
                    let batch1 = SyncController.WriteBatch(library: library,
                                                           object: .collection,
                                                           version: 1,
                                                           parameters: [["name": "A",
                                                                         "key": "AAAAAAAA",
                                                                         "version": 1]])
                    var all: [SyncController.Action]?
                    let expected: [SyncController.Action] = [.loadKeyPermissions,
                                                             .createLibraryActions(.specific([.custom(.myLibrary)]), .automatic),
                                                             .submitWriteBatch(batch1),
                                                             .createLibraryActions(.specific([.custom(.myLibrary)]), .forceDownloads),
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
                                                             .createLibraryActions(.specific([.custom(.myLibrary)]), .onlyWrites),
                                                             .submitWriteBatch(batch1)]
                    var updateCount = 0

                    let preconditionError = AFError.responseValidationFailed(reason: .unacceptableStatusCode(code: 412))

                    self.controller = self.performActionsTest(libraries: .specific([.custom(.myLibrary)]),
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
                    self.controller?.start(type: .normal, libraries: .specific([.custom(.myLibrary)]))

                    expect(all).toEventually(equal(expected))
                }
            }

            describe("fatal error handling") {
                it("doesn't process store version action") {
                    let initial: [SyncController.Action] = [.storeVersion(1, SyncControllerSpec.userLibrary, .group)]
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
                    let action = SyncController.DownloadBatch(library: SyncControllerSpec.userLibrary, object: .group,
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

                    let initial: [SyncController.Action] = [.syncVersions(SyncControllerSpec.userLibrary, .collection, 1)]
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

                    let initial: [SyncController.Action] = [.createLibraryActions(.all, .automatic)]
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

                    let initial: [SyncController.Action] = [.syncVersions(SyncControllerSpec.userLibrary, .group, nil)]
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
                it("should download items into a new library") {
                    let header = ["Last-Modified-Version" : "3"]
                    let library = SyncControllerSpec.userLibrary
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
                        case .group, .tag: break
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
                        case .group, .tag: break
                        }
                    }

                    objects.forEach { object in
                        let version: Int? = object == .group ? nil : 0
                        self.createStub(for: VersionsRequest<String>(libraryType: library,
                                                                     objectType: object, version: version),
                                        baseUrl: baseUrl, headers: header,
                                        response: (versionResponses[object] ?? [:]))
                    }
                    objects.forEach { object in
                        self.createStub(for: ObjectsRequest(libraryType: library, objectType: object, keys: (objectKeys[object] ?? "")),
                                        baseUrl: baseUrl, headers: header,
                                        response: (objectResponses[object] ?? [:]))
                    }
                    self.createStub(for: KeyRequest(), baseUrl: baseUrl, response: ["access": ["":""]])
                    self.createStub(for: SettingsRequest(libraryType: library, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    response: ["tagColors" : ["value": [["name": "A", "color": "#CC66CC"]], "version": 2]])
                    self.createStub(for: DeletionsRequest(libraryType: library, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    response: ["collections": [], "searches": [], "items": [], "tags": []])

                    self.controller = SyncController(userId: SyncControllerSpec.userId,
                                                     handler: SyncControllerSpec.syncHandler,
                                                     updateDataSource: SyncControllerSpec.emptyUpdateDataSource,
                                                     conflictDelays: SyncControllerSpec.conflictDelays)

                    waitUntil(timeout: 10) { doneAction in
                        self.controller?.reportFinish = { _ in
                            let realm = try! Realm(configuration: SyncControllerSpec.realmConfig)
                            realm.refresh()

                            let library = realm.objects(RCustomLibrary.self).first
                            expect(library).toNot(beNil())
                            expect(library?.type).to(equal(.myLibrary))

                            expect(library?.collections.count).to(equal(1))
                            expect(library?.items.count).to(equal(2))
                            expect(library?.searches.count).to(equal(1))
                            expect(library?.tags.count).to(equal(1))
                            expect(realm.objects(RCustomLibrary.self).count).to(equal(1))
                            expect(realm.objects(RGroup.self).count).to(equal(0))
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
                            expect(collection?.syncState).to(equal(.synced))
                            expect(collection?.version).to(equal(1))
                            expect(collection?.customLibrary?.type).to(equal(.myLibrary))
                            expect(collection?.parent).to(beNil())
                            expect(collection?.children.count).to(equal(0))

                            let item = realm.objects(RItem.self).filter("key = %@", "AAAAAAAA").first
                            expect(item).toNot(beNil())
                            expect(item?.title).to(equal("A"))
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
                            expect(item2?.title).to(equal("This is a note"))
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

                            let search = realm.objects(RSearch.self).first
                            expect(search?.key).to(equal("AAAAAAAA"))
                            expect(search?.version).to(equal(2))
                            expect(search?.name).to(equal("A"))
                            expect(search?.syncState).to(equal(.synced))
                            expect(search?.customLibrary?.type).to(equal(.myLibrary))
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
                }

                it("should download items into a new read-only group") {
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
                        case .tag: break
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
                        case .tag: break
                        }
                    }

                    let myLibrary = SyncControllerSpec.userLibrary
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
                    self.createStub(for: KeyRequest(), baseUrl: baseUrl, response: ["access": ["":""]])
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
                                                     updateDataSource: SyncControllerSpec.emptyUpdateDataSource,
                                                     conflictDelays: SyncControllerSpec.conflictDelays)

                    waitUntil(timeout: 10) { doneAction in
                        self.controller?.reportFinish = { _ in
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
                                .filter(Predicates.keyInLibrary(key: "AAAAAAAA", libraryId: .group(groupId))).first
                            expect(collection).toNot(beNil())
                            let item = realm.objects(RItem.self)
                                .filter(Predicates.keyInLibrary(key: "AAAAAAAA", libraryId: .group(groupId))).first
                            expect(item).toNot(beNil())
                            let item2 = realm.objects(RItem.self)
                                .filter(Predicates.keyInLibrary(key: "BBBBBBBB", libraryId: .group(groupId))).first
                            expect(item2).toNot(beNil())
                            let search = realm.objects(RSearch.self)
                                .filter(Predicates.keyInLibrary(key: "AAAAAAAA", libraryId: .group(groupId))).first
                            expect(search).toNot(beNil())
                            let tag = realm.objects(RTag.self)
                                .filter(Predicates.nameInLibrary(name: "A", libraryId: .group(groupId))).first
                            expect(tag).toNot(beNil())

                            doneAction()
                        }

                        self.controller?.start(type: .normal, libraries: .all)
                    }
                }

                it("should apply remote deletions") {
                    let header = ["Last-Modified-Version" : "3"]
                    let library = SyncControllerSpec.userLibrary
                    let itemToDelete = "CCCCCCCC"
                    let objects = SyncController.Object.allCases

                    let realm = SyncControllerSpec.realm
                    try! realm.write {
                        let myLibrary = SyncControllerSpec.realm.objects(RCustomLibrary.self).first
                        let item = RItem()
                        item.key = itemToDelete
                        item.title = "Delete me"
                        item.customLibrary = myLibrary
                        realm.add(item)
                    }

                    let predicate = Predicates.keyInLibrary(key: itemToDelete, libraryId: .custom(.myLibrary))
                    let toBeDeletedItem = realm.objects(RItem.self).filter(predicate).first
                    expect(toBeDeletedItem).toNot(beNil())

                    objects.forEach { object in
                        let version: Int? = object == .group ? nil : 0
                        self.createStub(for: VersionsRequest<String>(libraryType: library,
                                                                     objectType: object, version: version),
                                        baseUrl: baseUrl, headers: header,
                                        response: [:])
                    }
                    self.createStub(for: KeyRequest(), baseUrl: baseUrl, response: ["access": ["":""]])
                    self.createStub(for: SettingsRequest(libraryType: library, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    response: ["tagColors" : ["value": [], "version": 2]])
                    self.createStub(for: DeletionsRequest(libraryType: library, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    response: ["collections": [], "searches": [], "items": [itemToDelete], "tags": []])

                    self.controller = SyncController(userId: SyncControllerSpec.userId,
                                                     handler: SyncControllerSpec.syncHandler,
                                                     updateDataSource: SyncControllerSpec.emptyUpdateDataSource,
                                                     conflictDelays: SyncControllerSpec.conflictDelays)

                    waitUntil(timeout: 10) { doneAction in
                        self.controller?.reportFinish = { _ in
                            let realm = try! Realm(configuration: SyncControllerSpec.realmConfig)
                            realm.refresh()

                            let predicate = Predicates.keyInLibrary(key: itemToDelete, libraryId: .custom(.myLibrary))
                            let deletedItem = realm.objects(RItem.self).filter(predicate).first
                            expect(deletedItem).to(beNil())

                            doneAction()
                        }

                        self.controller?.start(type: .normal, libraries: .all)
                    }
                }

                it("should ignore remote deletions if local object changed") {
                    let header = ["Last-Modified-Version" : "3"]
                    let library = SyncControllerSpec.userLibrary
                    let itemToDelete = "DDDDDDDD"
                    let objects = SyncController.Object.allCases

                    let realm = SyncControllerSpec.realm
                    try! realm.write {
                        let myLibrary = SyncControllerSpec.realm.objects(RCustomLibrary.self).first
                        let item = RItem()
                        item.key = itemToDelete
                        item.title = "Delete me"
                        item.changedFields = .fields
                        item.customLibrary = myLibrary
                        realm.add(item)
                    }

                    let predicate = Predicates.keyInLibrary(key: itemToDelete, libraryId: .custom(.myLibrary))
                    let toBeDeletedItem = realm.objects(RItem.self).filter(predicate).first
                    expect(toBeDeletedItem).toNot(beNil())

                    var statusCode: Int32 = 412
                    let request = UpdatesRequest(libraryType: library, objectType: .item, params: [], version: 0)
                    stub(condition: request.stubCondition(with: baseUrl), response: { _ -> OHHTTPStubsResponse in
                        let code = statusCode
                        statusCode = 200
                        return OHHTTPStubsResponse(jsonObject: [:], statusCode: code, headers: header)
                    })
                    objects.forEach { object in
                        let version: Int? = object == .group ? nil : 0
                        self.createStub(for: VersionsRequest<String>(libraryType: library,
                                                                     objectType: object, version: version),
                                        baseUrl: baseUrl, headers: header,
                                        response: [:])
                    }
                    self.createStub(for: KeyRequest(), baseUrl: baseUrl, response: ["access": ["":""]])
                    self.createStub(for: SettingsRequest(libraryType: library, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    response: ["tagColors" : ["value": [], "version": 2]])
                    self.createStub(for: DeletionsRequest(libraryType: library, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    response: ["collections": [], "searches": [], "items": [itemToDelete], "tags": []])

                    self.controller = SyncController(userId: SyncControllerSpec.userId,
                                                     handler: SyncControllerSpec.syncHandler,
                                                     updateDataSource: SyncControllerSpec.updateDataSource,
                                                     conflictDelays: SyncControllerSpec.conflictDelays)

                    waitUntil(timeout: 10) { doneAction in
                        self.controller?.reportFinish = { result in
                            let realm = try! Realm(configuration: SyncControllerSpec.realmConfig)
                            realm.refresh()

                            switch result {
                            case .success(let data):
                                expect(data.0).to(contain(.resolveConflict(itemToDelete, library)))
                            case .failure:
                                fail("Sync aborted")
                            }

                            let predicate = Predicates.keyInLibrary(key: itemToDelete, libraryId: .custom(.myLibrary))
                            let deletedItem = realm.objects(RItem.self).filter(predicate).first
                            expect(deletedItem).toNot(beNil())

                            doneAction()
                        }

                        self.controller?.start(type: .normal, libraries: .all)
                    }
                }

                it("should handle new remote item referencing locally missing collection") {
                    let header = ["Last-Modified-Version" : "3"]
                    let library = SyncControllerSpec.userLibrary
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
                            let version: Int? = object == .group ? nil : 0
                            self.createStub(for: VersionsRequest<String>(libraryType: library,
                                                                         objectType: object, version: version),
                                            baseUrl: baseUrl, headers: header,
                                            response: [:])
                        }
                    }
                    self.createStub(for: KeyRequest(), baseUrl: baseUrl, response: ["access": ["":""]])
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
                                                     updateDataSource: SyncControllerSpec.emptyUpdateDataSource,
                                                     conflictDelays: SyncControllerSpec.conflictDelays)

                    waitUntil(timeout: 10) { doneAction in
                        self.controller?.reportFinish = { _ in
                            let realm = try! Realm(configuration: SyncControllerSpec.realmConfig)
                            realm.refresh()

                            let predicate = Predicates.keyInLibrary(key: itemKey, libraryId: .custom(.myLibrary))
                            let item = realm.objects(RItem.self).filter(predicate).first
                            expect(item).toNot(beNil())
                            expect(item?.syncState).to(equal(.synced))
                            expect(item?.collections.count).to(equal(1))

                            let collection = item?.collections.first
                            expect(collection).toNot(beNil())
                            expect(collection?.key).to(equal(collectionKey))
                            expect(collection?.syncState).to(equal(.dirty))

                            doneAction()
                        }

                        self.controller?.start(type: .normal, libraries: .all)
                    }
                }

                it("should include unsynced objects in sync queue") {
                    let header = ["Last-Modified-Version" : "3"]
                    let library = SyncControllerSpec.userLibrary
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
                        let library = realm.object(ofType: RCustomLibrary.self,
                                                   forPrimaryKey: RCustomLibraryType.myLibrary.rawValue)
                        let item = RItem()
                        item.key = unsyncedItemKey
                        item.syncState = .dirty
                        item.customLibrary = library
                        realm.add(item)
                    }

                    let predicate = Predicates.keyInLibrary(key: unsyncedItemKey, libraryId: .custom(.myLibrary))
                    let unsynced = realm.objects(RItem.self).filter(predicate).first
                    expect(unsynced).toNot(beNil())
                    expect(unsynced?.syncState).to(equal(.dirty))

                    objects.forEach { object in
                        if object == .item {
                            self.createStub(for: VersionsRequest<String>(libraryType: library, objectType: object, version: 0),
                                            baseUrl: baseUrl, headers: header,
                                            response: [responseItemKey: 3])
                        } else {
                            let version: Int? = object == .group ? nil : 0
                            self.createStub(for: VersionsRequest<String>(libraryType: library,
                                                                         objectType: object, version: version),
                                            baseUrl: baseUrl, headers: header,
                                            response: [:])
                        }
                    }
                    self.createStub(for: KeyRequest(), baseUrl: baseUrl, response: ["access": ["":""]])
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
                                                     updateDataSource: SyncControllerSpec.emptyUpdateDataSource,
                                                     conflictDelays: SyncControllerSpec.conflictDelays)

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

                            let newPred = Predicates.keyInLibrary(key: responseItemKey, libraryId: .custom(.myLibrary))
                            let newItem = realm.objects(RItem.self).filter(newPred).first
                            expect(newItem).toNot(beNil())
                            expect(newItem?.title).to(equal("A"))

                            let oldPred = Predicates.keyInLibrary(key: unsyncedItemKey, libraryId: .custom(.myLibrary))
                            let oldItem = realm.objects(RItem.self).filter(oldPred).first
                            expect(oldItem).toNot(beNil())
                            expect(oldItem?.title).to(equal("B"))
                            expect(oldItem?.syncState).to(equal(.synced))

                            doneAction()
                        }

                        self.controller?.start(type: .normal, libraries: .all)
                    }
                }

                it("should mark object as needsSync if not parsed correctly and syncRetries should be increased") {
                    let header = ["Last-Modified-Version" : "3"]
                    let library = SyncControllerSpec.userLibrary
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
                            let version: Int? = object == .group ? nil : 0
                            self.createStub(for: VersionsRequest<String>(libraryType: library,
                                                                         objectType: object, version: version),
                                            baseUrl: baseUrl, headers: header,
                                            response: [:])
                        }
                    }
                    self.createStub(for: KeyRequest(), baseUrl: baseUrl, response: ["access": ["":""]])
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
                                                     updateDataSource: SyncControllerSpec.emptyUpdateDataSource,
                                                     conflictDelays: SyncControllerSpec.conflictDelays)

                    waitUntil(timeout: 10) { doneAction in
                        self.controller?.reportFinish = { result in
                            let realm = try! Realm(configuration: SyncControllerSpec.realmConfig)
                            realm.refresh()

                            let correctPred = Predicates.keyInLibrary(key: correctKey, libraryId: .custom(.myLibrary))
                            let correctItem = realm.objects(RItem.self).filter(correctPred).first
                            expect(correctItem).toNot(beNil())
                            expect(correctItem?.syncState).to(equal(.synced))
                            expect(correctItem?.syncRetries).to(equal(0))

                            let incorrectPred = Predicates.keyInLibrary(key: incorrectKey, libraryId: .custom(.myLibrary))
                            let incorrectItem = realm.objects(RItem.self).filter(incorrectPred).first
                            expect(incorrectItem).toNot(beNil())
                            expect(incorrectItem?.syncState).to(equal(.dirty))
                            expect(incorrectItem?.syncRetries).to(equal(1))

                            doneAction()
                        }

                        self.controller?.start(type: .normal, libraries: .all)
                    }
                }

                it("should ignore errors when saving downloaded objects") {
                    let header = ["Last-Modified-Version" : "2"]
                    let library = SyncControllerSpec.userLibrary
                    let objects = SyncController.Object.allCases

                    var versionResponses: [SyncController.Object: Any] = [:]
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
                        case .group, .tag, .trash: break
                        }
                    }

                    let objectKeys: [SyncController.Object: String] = [.collection: "AAAAAAAA,BBBBBBBB,CCCCCCCC",
                                                                       .search: "GGGGGGGG,HHHHHHHH,IIIIIIII",
                                                                       .item: "DDDDDDDD,EEEEEEEE,FFFFFFFF"]
                    var objectResponses: [SyncController.Object: Any] = [:]
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
                                                       // Unknown field - should be synced, unknown field ignored
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
                                                       // Unknown field - should be queued
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
                        case .group, .tag, .trash: break
                        }
                    }

                    objects.forEach { object in
                        let version: Int? = object == .group ? nil : 0
                        self.createStub(for: VersionsRequest<String>(libraryType: library,
                                                                     objectType: object, version: version),
                                        baseUrl: baseUrl, headers: header,
                                        response: (versionResponses[object] ?? [:]))
                    }
                    objects.forEach { object in
                        self.createStub(for: ObjectsRequest(libraryType: library, objectType: object, keys: (objectKeys[object] ?? "")),
                                        baseUrl: baseUrl, headers: header,
                                        response: (objectResponses[object] ?? [:]))
                    }
                    self.createStub(for: KeyRequest(), baseUrl: baseUrl, response: ["access": ["":""]])
                    self.createStub(for: SettingsRequest(libraryType: library, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    response: ["tagColors" : ["value": [["name": "A", "color": "#CC66CC"]], "version": 2]])
                    self.createStub(for: DeletionsRequest(libraryType: library, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    response: ["collections": [], "searches": [], "items": [], "tags": []])

                    self.controller = SyncController(userId: SyncControllerSpec.userId,
                                                     handler: SyncControllerSpec.syncHandler,
                                                     updateDataSource: SyncControllerSpec.emptyUpdateDataSource,
                                                     conflictDelays: SyncControllerSpec.conflictDelays)

                    waitUntil(timeout: 10) { doneAction in
                        self.controller?.reportFinish = { _ in
                            let realm = try! Realm(configuration: SyncControllerSpec.realmConfig)
                            realm.refresh()

                            let library = realm.objects(RCustomLibrary.self).first
                            expect(library).toNot(beNil())
                            expect(library?.type).to(equal(.myLibrary))

                            expect(library?.collections.count).to(equal(4))
                            expect(library?.items.count).to(equal(3))
                            expect(library?.searches.count).to(equal(3))
                            expect(realm.objects(RCollection.self).count).to(equal(4))
                            expect(realm.objects(RSearch.self).count).to(equal(3))
                            expect(realm.objects(RItem.self).count).to(equal(3))

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
                            expect(collection3).toNot(beNil())
                            expect(collection3?.name).to(equal("C"))
                            expect(collection3?.syncState).to(equal(.synced))
                            expect(collection3?.version).to(equal(1))
                            expect(collection3?.customLibrary?.type).to(equal(.myLibrary))
                            expect(collection3?.parent).to(beNil())
                            expect(collection3?.children.count).to(equal(0))

                            let collection4 = realm.objects(RCollection.self).filter("key = %@", "ZZZZZZZZ").first
                            expect(collection4).toNot(beNil())
                            expect(collection4?.syncState).to(equal(.dirty))
                            expect(collection4?.customLibrary?.type).to(equal(.myLibrary))
                            expect(collection4?.parent).to(beNil())
                            expect(collection4?.children.count).to(equal(1))

                            let item = realm.objects(RItem.self).filter("key = %@", "DDDDDDDD").first
                            expect(item).toNot(beNil())
                            expect(item?.syncState).to(equal(.dirty))
                            expect(item?.parent).to(beNil())
                            expect(item?.children.count).to(equal(0))

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

                            let search = realm.objects(RSearch.self).first
                            expect(search?.key).to(equal("GGGGGGGG"))
                            expect(search?.name).to(equal("G"))
                            expect(search?.syncState).to(equal(.dirty))
                            expect(search?.conditions.count).to(equal(0))

                            let search2 = realm.objects(RSearch.self).first
                            expect(search2?.key).to(equal("HHHHHHHH"))
                            expect(search2?.name).to(equal("H"))
                            expect(search2?.syncState).to(equal(.dirty))
                            expect(search2?.conditions.count).to(equal(0))

                            doneAction()
                        }

                        self.controller?.start(type: .normal, libraries: .all)
                    }
                }

                it("should add items that exist remotely in a locally deleted," +
                   " remotely modified collection back to collection") {
                    let header = ["Last-Modified-Version" : "1"]
                    let library = SyncControllerSpec.userLibrary
                    let objects = SyncController.Object.allCases
                    let collectionKey = "AAAAAAAA"

                    let realm = SyncControllerSpec.realm
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
                        item1.title = "B"
                        item1.customLibrary = library
                        item1.collections.append(collection)
                        realm.add(item1)

                        let item2 = RItem()
                        item2.key = "CCCCCCCC"
                        item2.title = "C"
                        item2.customLibrary = library
                        item2.collections.append(collection)
                        realm.add(item2)
                    }

                    let versionResponses: [SyncController.Object: Any] = [.collection: [collectionKey: 1]]
                    let objectKeys: [SyncController.Object: String] = [.collection: collectionKey]
                    let collectionData: [[String: Any]] = [["key": collectionKey,
                                                            "version": 1,
                                                            "library": ["id": 0, "type": "user", "name": "A"],
                                                            "data": ["name": "A"]]]
                    let objectResponses: [SyncController.Object: Any] = [.collection: collectionData]

                    self.createStub(for: SubmitDeletionsRequest(libraryType: library, objectType: .collection,
                                                                keys: [collectionKey], version: 0),
                                    baseUrl: baseUrl, headers: header, statusCode: 412, response: [:])
                    objects.forEach { object in
                        let version: Int? = object == .group ? nil : 0
                        self.createStub(for: VersionsRequest<String>(libraryType: library,
                                                                     objectType: object, version: version),
                                        baseUrl: baseUrl, headers: header,
                                        response: (versionResponses[object] ?? [:]))
                    }
                    objects.forEach { object in
                        self.createStub(for: ObjectsRequest(libraryType: library, objectType: object,
                                                            keys: (objectKeys[object] ?? "")),
                                        baseUrl: baseUrl, headers: header,
                                        response: (objectResponses[object] ?? [:]))
                    }
                    self.createStub(for: KeyRequest(), baseUrl: baseUrl, response: ["access": ["":""]])
                    self.createStub(for: SettingsRequest(libraryType: library, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    response: ["tagColors" : ["value": [["name": "A", "color": "#CC66CC"]], "version": 1]])
                    self.createStub(for: DeletionsRequest(libraryType: library, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    response: ["collections": [], "searches": [], "items": [], "tags": []])

                    self.controller = SyncController(userId: SyncControllerSpec.userId,
                                                     handler: SyncControllerSpec.syncHandler,
                                                     updateDataSource: SyncControllerSpec.updateDataSource,
                                                     conflictDelays: SyncControllerSpec.conflictDelays)

                    waitUntil(timeout: 10) { doneAction in
                        self.controller?.reportFinish = { _ in
                            let realm = try! Realm(configuration: SyncControllerSpec.realmConfig)
                            realm.refresh()

                            let library = realm.objects(RCustomLibrary.self).first
                            expect(library).toNot(beNil())
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

                        self.controller?.start(type: .normal, libraries: .all)
                    }
                }

                it("should add locally deleted items that exist remotely in a locally deleted, remotely modified" +
                   " collection to sync queue and remove from delete log") {
                    let header = ["Last-Modified-Version" : "1"]
                    let library = SyncControllerSpec.userLibrary
                    let objects = SyncController.Object.allCases
                    let collectionKey = "AAAAAAAA"
                    let deletedItemKey = "CCCCCCCC"

                    let realm = SyncControllerSpec.realm
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
                        item1.title = "B"
                        item1.customLibrary = library
                        item1.collections.append(collection)
                        realm.add(item1)

                        let item2 = RItem()
                        item2.key = deletedItemKey
                        item2.title = "C"
                        item2.deleted = true
                        item2.customLibrary = library
                        item2.collections.append(collection)
                        realm.add(item2)
                    }

                    let versionResponses: [SyncController.Object: Any] = [.collection: [collectionKey: 2]]
                    let objectKeys: [SyncController.Object: String] = [.collection: collectionKey]
                    let collectionData: [[String: Any]] = [["key": collectionKey,
                                                            "version": 2,
                                                            "library": ["id": 0, "type": "user", "name": "A"],
                                                            "data": ["name": "A"]]]
                    let objectResponses: [SyncController.Object: Any] = [.collection: collectionData]

                    self.createStub(for: KeyRequest(), baseUrl: baseUrl, response: ["access": ["":""]])
                    self.createStub(for: SubmitDeletionsRequest(libraryType: library, objectType: .collection,
                                                                keys: [collectionKey], version: 1),
                                    baseUrl: baseUrl, headers: header, statusCode: 412, response: [:])
                    self.createStub(for: SubmitDeletionsRequest(libraryType: library, objectType: .item,
                                                                keys: [deletedItemKey], version: 1),
                                    baseUrl: baseUrl, headers: header, statusCode: 412, response: [:])
                    objects.forEach { object in
                        let version: Int? = object == .group ? nil : 1
                        self.createStub(for: VersionsRequest<String>(libraryType: library,
                                                                     objectType: object, version: version),
                                        baseUrl: baseUrl, headers: header,
                                        response: (versionResponses[object] ?? [:]))
                    }
                    objects.forEach { object in
                        self.createStub(for: ObjectsRequest(libraryType: library, objectType: object,
                                                            keys: (objectKeys[object] ?? "")),
                                        baseUrl: baseUrl, headers: header,
                                        response: (objectResponses[object] ?? [:]))
                    }
                    self.createStub(for: SettingsRequest(libraryType: library, version: 1),
                                    baseUrl: baseUrl, headers: header,
                                    response: ["tagColors" : ["value": [["name": "A", "color": "#CC66CC"]], "version": 1]])
                    self.createStub(for: DeletionsRequest(libraryType: library, version: 1),
                                    baseUrl: baseUrl, headers: header,
                                    response: ["collections": [], "searches": [], "items": [], "tags": []])

                    self.controller = SyncController(userId: SyncControllerSpec.userId,
                                                     handler: SyncControllerSpec.syncHandler,
                                                     updateDataSource: SyncControllerSpec.updateDataSource,
                                                     conflictDelays: SyncControllerSpec.conflictDelays)

                    waitUntil(timeout: 10) { doneAction in
                        self.controller?.reportFinish = { _ in
                            let realm = try! Realm(configuration: SyncControllerSpec.realmConfig)
                            realm.refresh()

                            let library = realm.objects(RCustomLibrary.self).first
                            expect(library).toNot(beNil())
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

                        self.controller?.start(type: .normal, libraries: .all)
                    }
                }
            }

            describe("Upload") {
                it("should update collection and item") {
                    let oldVersion = 3
                    let newVersion = oldVersion + 1
                    let collectionKey = "AAAAAAAA"
                    let itemKey = "BBBBBBBB"

                    let realm = SyncControllerSpec.realm
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

                    let library = SyncControllerSpec.userLibrary

                    let collectionUpdate = UpdatesRequest(libraryType: library, objectType: .collection,
                                                          params: [], version: oldVersion)
                    let collectionConditions = collectionUpdate.stubCondition(with: baseUrl)
                    stub(condition: collectionConditions, response: { request -> OHHTTPStubsResponse in
                        let params = request.httpBodyStream.flatMap({ self.jsonParameters(from: $0) })
                        expect(params?.count).to(equal(1))
                        let firstParams = params?.first ?? [:]
                        expect(firstParams["key"] as? String).to(equal(collectionKey))
                        expect(firstParams["version"] as? Int).to(equal(oldVersion))
                        expect(firstParams["name"] as? String).to(equal("New name"))
                        return OHHTTPStubsResponse(jsonObject: ["success": ["0": [:]], "unchanged": [], "failed": []],
                                                   statusCode: 200, headers: ["Last-Modified-Version": "\(newVersion)"])
                    })

                    let itemUpdate = UpdatesRequest(libraryType: library, objectType: .item,
                                                    params: [], version: oldVersion)
                    let itemConditions = itemUpdate.stubCondition(with: baseUrl)
                    stub(condition: itemConditions, response: { request -> OHHTTPStubsResponse in
                        let params = request.httpBodyStream.flatMap({ self.jsonParameters(from: $0) })
                        expect(params?.count).to(equal(1))
                        let firstParams = params?.first ?? [:]
                        expect(firstParams["key"] as? String).to(equal(itemKey))
                        expect(firstParams["version"] as? Int).to(equal(oldVersion))
                        expect(firstParams["title"] as? String).to(equal("New item"))
                        expect(firstParams["numPages"] as? String).to(equal("1"))
                        expect(firstParams["callNumber"]).to(beNil())
                        return OHHTTPStubsResponse(jsonObject: ["success": ["0": [:]], "unchanged": [], "failed": []],
                                                   statusCode: 200, headers: ["Last-Modified-Version": "\(newVersion)"])
                    })
                    self.createStub(for: KeyRequest(), baseUrl: baseUrl, response: ["access": ["":""]])

                    self.controller = SyncController(userId: SyncControllerSpec.userId,
                                                     handler: SyncControllerSpec.syncHandler,
                                                     updateDataSource: SyncControllerSpec.updateDataSource,
                                                     conflictDelays: SyncControllerSpec.conflictDelays)

                    waitUntil(timeout: 10) { doneAction in
                        self.controller?.reportFinish = { _ in
                            let realm = try! Realm(configuration: SyncControllerSpec.realmConfig)
                            realm.refresh()

                            let library = realm.object(ofType: RCustomLibrary.self,
                                                       forPrimaryKey: RCustomLibraryType.myLibrary.rawValue)

                            let versions = library?.versions
                            expect(versions?.collections).to(equal(newVersion))
                            expect(versions?.items).to(equal(newVersion))

                            let collectionPred = Predicates.keyInLibrary(key: collectionKey, libraryId: .custom(.myLibrary))
                            let collection = realm.objects(RCollection.self).filter(collectionPred).first
                            expect(collection?.version).to(equal(newVersion))
                            expect(collection?.rawChangedFields).to(equal(0))

                            let itemPred = Predicates.keyInLibrary(key: itemKey, libraryId: .custom(.myLibrary))
                            let item = realm.objects(RItem.self).filter(itemPred).first
                            expect(item?.version).to(equal(newVersion))
                            expect(item?.rawChangedFields).to(equal(0))
                            item?.fields.forEach({ field in
                                expect(field.changed).to(beFalse())
                            })

                            doneAction()
                        }
                        self.controller?.start(type: .normal, libraries: .specific([.custom(.myLibrary)]))
                    }
                }

                it("should upload child item after parent item") {
                    let oldVersion = 3
                    let newVersion = oldVersion + 1
                    let parentKey = "BBBBBBBB"
                    let childKey = "CCCCCCCC"
                    let otherKey = "AAAAAAAA"

                    let realm = SyncControllerSpec.realm
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

                    let library = SyncControllerSpec.userLibrary

                    let update = UpdatesRequest(libraryType: library, objectType: .item,
                                                params: [], version: oldVersion)
                    let conditions = update.stubCondition(with: baseUrl)
                    stub(condition: conditions, response: { request -> OHHTTPStubsResponse in
                        guard let params = request.httpBodyStream.flatMap({ self.jsonParameters(from: $0) }) else {
                            fail("parameters not found")
                            fatalError()
                        }

                        expect(params.count).to(equal(3))
                        let parentPos = params.index(where: { ($0["key"] as? String) == parentKey }) ?? -1
                        let childPos = params.index(where: { ($0["key"] as? String) == childKey }) ?? -1
                        expect(parentPos).toNot(equal(-1))
                        expect(childPos).toNot(equal(-1))
                        expect(parentPos).to(beLessThan(childPos))

                        return OHHTTPStubsResponse(jsonObject: ["success": ["0": [:]], "unchanged": [], "failed": []],
                                                   statusCode: 200, headers: ["Last-Modified-Version": "\(newVersion)"])
                    })
                    self.createStub(for: KeyRequest(), baseUrl: baseUrl, response: ["access": ["":""]])

                    self.controller = SyncController(userId: SyncControllerSpec.userId,
                                                     handler: SyncControllerSpec.syncHandler,
                                                     updateDataSource: SyncControllerSpec.updateDataSource,
                                                     conflictDelays: SyncControllerSpec.conflictDelays)

                    waitUntil(timeout: 10) { doneAction in
                        self.controller?.reportFinish = { _ in
                            doneAction()
                        }
                        self.controller?.start(type: .normal, libraries: .specific([.custom(.myLibrary)]))
                    }
                }

                it("should upload child collection after parent collection") {
                    let oldVersion = 3
                    let newVersion = oldVersion + 1
                    let firstKey = "AAAAAAAA"
                    let secondKey = "BBBBBBBB"
                    let thirdKey = "CCCCCCCC"

                    let realm = SyncControllerSpec.realm
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

                    let library = SyncControllerSpec.userLibrary

                    let update = UpdatesRequest(libraryType: library, objectType: .collection,
                                                params: [], version: oldVersion)
                    let conditions = update.stubCondition(with: baseUrl)
                    stub(condition: conditions, response: { request -> OHHTTPStubsResponse in
                        guard let params = request.httpBodyStream.flatMap({ self.jsonParameters(from: $0) }) else {
                            fail("parameters not found")
                            fatalError()
                        }

                        expect(params.count).to(equal(3))
                        expect(params[0]["key"] as? String).to(equal(firstKey))
                        expect(params[1]["key"] as? String).to(equal(secondKey))
                        expect(params[2]["key"] as? String).to(equal(thirdKey))

                        return OHHTTPStubsResponse(jsonObject: ["success": ["0": [:]], "unchanged": [], "failed": []],
                                                   statusCode: 200, headers: ["Last-Modified-Version": "\(newVersion)"])
                    })
                    self.createStub(for: KeyRequest(), baseUrl: baseUrl, response: ["access": ["":""]])

                    self.controller = SyncController(userId: SyncControllerSpec.userId,
                                                     handler: SyncControllerSpec.syncHandler,
                                                     updateDataSource: SyncControllerSpec.updateDataSource,
                                                     conflictDelays: SyncControllerSpec.conflictDelays)

                    waitUntil(timeout: 10) { doneAction in
                        self.controller?.reportFinish = { _ in
                            doneAction()
                        }
                        self.controller?.start(type: .normal, libraries: .specific([.custom(.myLibrary)]))
                    }
                }

                it("should update library version after upload") {
                    let oldVersion = 3
                    let newVersion = oldVersion + 10

                    let realm = SyncControllerSpec.realm
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

                    let library = SyncControllerSpec.userLibrary

                    let update = UpdatesRequest(libraryType: library, objectType: .collection,
                                                params: [], version: oldVersion)
                    self.createStub(for: KeyRequest(), baseUrl: baseUrl, response: ["access": ["":""]])
                    self.createStub(for: update, baseUrl: baseUrl,
                                    headers: ["Last-Modified-Version": "\(newVersion)"],
                                    statusCode: 200,
                                    response: ["success": ["0": [:]], "unchanged": [], "failed": []])

                    self.controller = SyncController(userId: SyncControllerSpec.userId,
                                                     handler: SyncControllerSpec.syncHandler,
                                                     updateDataSource: SyncControllerSpec.updateDataSource,
                                                     conflictDelays: SyncControllerSpec.conflictDelays)

                    waitUntil(timeout: 10) { doneAction in
                        self.controller?.reportFinish = { _ in
                            let realm = try! Realm(configuration: SyncControllerSpec.realmConfig)
                            realm.refresh()

                            let library = realm.object(ofType: RCustomLibrary.self,
                                                       forPrimaryKey: RCustomLibraryType.myLibrary.rawValue)

                            expect(library?.versions?.collections).to(equal(newVersion))

                            doneAction()
                        }
                        self.controller?.start(type: .normal, libraries: .specific([.custom(.myLibrary)]))
                    }
                }

                it("should process downloads after upload failure") {
                    let header = ["Last-Modified-Version" : "3"]
                    let library = SyncControllerSpec.userLibrary
                    let objects = SyncController.Object.allCases

                    var downloadCalled = false

                    var statusCode: Int32 = 412
                    let request = UpdatesRequest(libraryType: library, objectType: .item, params: [], version: 0)
                    stub(condition: request.stubCondition(with: baseUrl), response: { _ -> OHHTTPStubsResponse in
                        let code = statusCode
                        statusCode = 200
                        return OHHTTPStubsResponse(jsonObject: [:], statusCode: code, headers: header)
                    })
                    objects.forEach { object in
                        let version: Int? = object == .group ? nil : 0
                        self.createStub(for: VersionsRequest<String>(libraryType: library,
                                                                     objectType: object, version: version),
                                        baseUrl: baseUrl, headers: header, response: [:])
                    }
                    stub(condition: SettingsRequest(libraryType: library, version: 0).stubCondition(with: baseUrl),
                         response: { _ -> OHHTTPStubsResponse in
                        downloadCalled = true
                        return OHHTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: header)
                    })
                    self.createStub(for: KeyRequest(), baseUrl: baseUrl, response: ["access": ["":""]])
                    self.createStub(for: DeletionsRequest(libraryType: library, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    response: ["collections": [], "searches": [], "items": [], "tags": []])

                    self.controller = SyncController(userId: SyncControllerSpec.userId,
                                                     handler: SyncControllerSpec.syncHandler,
                                                     updateDataSource: SyncControllerSpec.emptyUpdateDataSource,
                                                     conflictDelays: SyncControllerSpec.conflictDelays)

                    waitUntil(timeout: 10) { doneAction in
                        self.controller?.reportFinish = { _ in
                            expect(downloadCalled).to(beTrue())
                            doneAction()
                        }

                        self.controller?.start(type: .normal, libraries: .all)
                    }
                }

                it("should upload local deletions") {
                    let header = ["Last-Modified-Version" : "1"]
                    let library = SyncControllerSpec.userLibrary
                    let collectionKey = "AAAAAAAA"
                    let searchKey = "BBBBBBBB"
                    let itemKey = "CCCCCCCC"

                    let realm = SyncControllerSpec.realm
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
                        item.title = "Deleted item"
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

                    self.createStub(for: KeyRequest(), baseUrl: baseUrl, response: ["access": ["":""]])
                    self.createStub(for: SubmitDeletionsRequest(libraryType: library, objectType: .collection,
                                                                keys: [collectionKey], version: 0),
                                    baseUrl: baseUrl, headers: header, response: [:])
                    self.createStub(for: SubmitDeletionsRequest(libraryType: library, objectType: .search,
                                                                keys: [searchKey], version: 0),
                                    baseUrl: baseUrl, headers: header, response: [:])
                    self.createStub(for: SubmitDeletionsRequest(libraryType: library, objectType: .item,
                                                                keys: [itemKey], version: 0),
                                    baseUrl: baseUrl, headers: header, response: [:])

                    self.controller = SyncController(userId: SyncControllerSpec.userId,
                                                     handler: SyncControllerSpec.syncHandler,
                                                     updateDataSource: SyncControllerSpec.updateDataSource,
                                                     conflictDelays: SyncControllerSpec.conflictDelays)

                    waitUntil(timeout: 10) { doneAction in
                        self.controller?.reportFinish = { _ in
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

                        self.controller?.start(type: .normal, libraries: .all)
                    }
                }

                it("should delay on second upload conflict") {
                    let header = ["Last-Modified-Version" : "3"]
                    let library = SyncControllerSpec.userLibrary
                    let itemToDelete = "DDDDDDDD"
                    let objects = SyncController.Object.allCases

                    let realm = SyncControllerSpec.realm
                    try! realm.write {
                        let myLibrary = SyncControllerSpec.realm.objects(RCustomLibrary.self).first
                        let item = RItem()
                        item.key = itemToDelete
                        item.title = "Delete me"
                        item.changedFields = .fields
                        item.customLibrary = myLibrary
                        realm.add(item)
                    }

                    let predicate = Predicates.keyInLibrary(key: itemToDelete, libraryId: .custom(.myLibrary))
                    let toBeDeletedItem = realm.objects(RItem.self).filter(predicate).first
                    expect(toBeDeletedItem).toNot(beNil())

                    var retryCount = 0
                    let request = UpdatesRequest(libraryType: library, objectType: .item, params: [], version: 0)
                    stub(condition: request.stubCondition(with: baseUrl), response: { _ -> OHHTTPStubsResponse in
                        retryCount += 1
                        return OHHTTPStubsResponse(jsonObject: [:], statusCode: (retryCount <= 2 ? 412 : 200), headers: header)
                    })
                    objects.forEach { object in
                        let version: Int? = object == .group ? nil : 0
                        self.createStub(for: VersionsRequest<String>(libraryType: library,
                                                                     objectType: object, version: version),
                                        baseUrl: baseUrl, headers: header,
                                        response: [:])
                    }
                    self.createStub(for: KeyRequest(), baseUrl: baseUrl, response: ["access": ["":""]])
                    self.createStub(for: SettingsRequest(libraryType: library, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    response: ["tagColors" : ["value": [], "version": 2]])
                    self.createStub(for: DeletionsRequest(libraryType: library, version: 0),
                                    baseUrl: baseUrl, headers: header,
                                    response: ["collections": [], "searches": [], "items": [itemToDelete], "tags": []])

                    var lastDelay: Int?
                    self.controller = SyncController(userId: SyncControllerSpec.userId,
                                                     handler: SyncControllerSpec.syncHandler,
                                                     updateDataSource: SyncControllerSpec.updateDataSource,
                                                     conflictDelays: SyncControllerSpec.conflictDelays)
                    self.controller?.reportDelay = { delay in
                        lastDelay = delay
                    }

                    waitUntil(timeout: 15) { doneAction in
                        self.controller?.reportFinish = { _ in
                            expect(lastDelay).to(equal(3))
                            expect(retryCount).to(equal(3))

                            let realm = try! Realm(configuration: SyncControllerSpec.realmConfig)
                            realm.refresh()

                            let predicate = Predicates.keyInLibrary(key: itemToDelete, libraryId: .custom(.myLibrary))
                            let deletedItem = realm.objects(RItem.self).filter(predicate).first
                            expect(deletedItem).toNot(beNil())

                            doneAction()
                        }
                        self.controller?.start(type: .normal, libraries: .all)
                    }
                }
            }

            it("should make only one request if in sync") {
                let library = SyncControllerSpec.userLibrary
                let expected: [SyncController.Action] = [.loadKeyPermissions, .syncVersions(library, .group, nil)]

                self.createStub(for: VersionsRequest<String>(libraryType: library, objectType: .group, version: nil),
                                baseUrl: baseUrl, headers: nil, statusCode: 304, response: [:])
                self.createStub(for: KeyRequest(), baseUrl: baseUrl, response: ["access": ["":""]])

                self.controller = SyncController(userId: SyncControllerSpec.userId,
                                                 handler: SyncControllerSpec.syncHandler,
                                                 updateDataSource: SyncControllerSpec.emptyUpdateDataSource,
                                                 conflictDelays: SyncControllerSpec.conflictDelays)

                waitUntil(timeout: 10) { doneAction in
                    self.controller?.reportFinish = { result in
                        switch result {
                        case .success(let data):
                            expect(data.0).to(equal(expected))
                        default:
                            fail("Test reported unexpected failure")
                        }

                        doneAction()
                    }

                    self.controller?.start(type: .normal, libraries: .all)
                }
            }
        }
    }

    private func jsonParameters(from stream: InputStream) -> [[String: Any]] {
        let json = try? JSONSerialization.jsonObject(with: stream.data, options: .allowFragments)
        return (json as? [[String: Any]]) ?? []
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
                                        updateDataSource: SyncControllerSpec.emptyUpdateDataSource,
                                        conflictDelays: SyncControllerSpec.conflictDelays)

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
        let dataSource = TestDataSource(writeBatches: updates, deleteBatches: [])
        let controller = SyncController(userId: SyncControllerSpec.userId,
                                        handler: handler, updateDataSource: dataSource,
                                        conflictDelays: SyncControllerSpec.conflictDelays)

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
                                        updateDataSource: SyncControllerSpec.emptyUpdateDataSource,
                                        conflictDelays: SyncControllerSpec.conflictDelays)

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
    case loadSpecificGroups([LibraryIdentifier])
    case syncVersions(SyncController.Object)
    case storeObject(SyncController.Object)
    case resync(SyncController.Object)
    case storeVersion(SyncController.Library)
    case markResync(SyncController.Object)
    case syncDeletions(SyncController.Library)
    case syncSettings(SyncController.Library)
    case submitUpdate(SyncController.Library, SyncController.Object)
    case submitDeletion(SyncController.Library, SyncController.Object)
}

fileprivate class TestHandler: SyncActionHandler {
    func loadPermissions() -> Single<KeyResponse> {
        return Single.just(KeyResponse())
    }

    var requestResult: ((TestAction) -> Single<()>)?

    private func result(for action: TestAction) -> Single<()> {
        return self.requestResult?(action) ?? Single.just(())
    }

    func loadAllLibraryData() -> Single<[LibraryData]> {
        return self.result(for: .loadGroups).flatMap {
            let data = LibraryData(identifier: .group(SyncControllerSpec.groupId), name: "",
                                   versions: SyncControllerSpec.groupIdVersions)
            return Single.just([data])
        }
    }

    func loadLibraryData(for libraryIds: [LibraryIdentifier]) -> Single<[LibraryData]> {
        return self.result(for: .loadSpecificGroups(libraryIds)).flatMap { _ in
            return Single.just(libraryIds.map({ LibraryData(identifier: $0, name: "",
                                                            versions: SyncControllerSpec.groupIdVersions) }))
        }
    }

    func synchronizeVersions(for library: SyncController.Library, object: SyncController.Object,
                             since sinceVersion: Int?, current currentVersion: Int?,
                             syncType: SyncController.SyncType) -> Single<(Int, [Any])> {
        return self.result(for: .syncVersions(object)).flatMap {
            let data = SyncControllerSpec.syncVersionData
            return Single.just((data.0, (0..<data.1).map({ $0.description })))
        }
    }

    func synchronizeGroupVersions(library: SyncController.Library, syncType: SyncController.SyncType) -> Single<(Int, [Int], [(Int, String)])> {
        return self.result(for: .syncVersions(.group)).flatMap {
            let data = SyncControllerSpec.syncVersionData
            return Single.just((data.0, Array(0..<data.1), []))
        }
    }

    func markForResync(keys: [Any], library: SyncController.Library, object: SyncController.Object) -> Completable {
        return self.result(for: .markResync(object)).asCompletable()
    }

    func fetchAndStoreObjects(with keys: [Any], library: SyncController.Library, object: SyncController.Object,
                              version: Int, userId: Int) -> Single<([String], [Error], [StoreItemsError])> {
        let keys = SyncControllerSpec.expectedKeys
        return self.result(for: .storeObject(object)).flatMap({ return Single.just((keys, [], [])) })
    }

    func storeVersion(_ version: Int, for library: SyncController.Library, type: UpdateVersionType) -> Completable {
        return self.result(for: .storeVersion(.group(SyncControllerSpec.groupId))).asCompletable()
    }

    func synchronizeDeletions(for library: SyncController.Library, since sinceVersion: Int,
                              current currentVersion: Int?) -> Single<[String]> {
        return self.result(for: .syncDeletions(library)).flatMap({ return Single.just([]) })
    }

    func synchronizeSettings(for library: SyncController.Library, current currentVersion: Int?,
                             since version: Int?) -> Single<(Bool, Int)> {
        return self.result(for: .syncSettings(library)).flatMap {
            let data = SyncControllerSpec.syncVersionData
            return Single.just((true, data.0))
        }
    }

    func submitUpdate(for library: SyncController.Library, object: SyncController.Object, since version: Int, parameters: [[String : Any]]) -> Single<(Int, Error?)> {
        return self.result(for: .submitUpdate(library, object)).flatMap {
            let data = SyncControllerSpec.syncVersionData
            return Single.just((data.0, nil))
        }
    }

    func submitDeletion(for library: SyncController.Library, object: SyncController.Object, since version: Int, keys: [String]) -> Single<Int> {
        return self.result(for: .submitDeletion(library, object)).flatMap {
            let data = SyncControllerSpec.syncVersionData
            return Single.just(data.0)
        }
    }
}

fileprivate class TestDataSource: SyncUpdateDataSource {
    private let writeBatches: [SyncController.WriteBatch]
    private let deleteBatches: [SyncController.DeleteBatch]

    init(writeBatches: [SyncController.WriteBatch], deleteBatches: [SyncController.DeleteBatch]) {
        self.writeBatches = writeBatches
        self.deleteBatches = deleteBatches
    }

    func updates(for library: SyncController.Library, versions: Versions) throws -> [SyncController.WriteBatch] {
        return self.writeBatches
    }

    func deletions(for library: SyncController.Library, versions: Versions) throws -> [SyncController.DeleteBatch] {
        return self.deleteBatches
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
