//
//  SyncControllerSpec.swift
//  ZoteroTests
//
//  Created by Michal Rentka on 08/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

@testable import Zotero

import Nimble
import Quick
import RxSwift

fileprivate struct TestErrors {
    static let nonFatal = SyncActionHandlerError.expired
    static let versionMismatch = SyncActionHandlerError.versionMismatch
    static let fatal = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: nil)
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

fileprivate typealias ActionTest = ([QueueAction], @escaping (TestAction) -> Single<()>,
                                    @escaping ([QueueAction]) -> Void) -> SyncController
fileprivate typealias ErrorTest = ([QueueAction], @escaping (TestAction) -> Single<()>,
                                   @escaping (Error) -> Void) -> SyncController

class SyncControllerSpec: QuickSpec {
    fileprivate static let groupId = 10
    private let userId = 100

    fileprivate static var syncVersionData: (Int, Int) = (0, 0) // version, object count
    fileprivate static var expectedKeys: [String] = []
    fileprivate static var groupIdVersions: Versions = Versions(collections: 0, items: 0, trash: 0, searches: 0,
                                                                deletions: 0, settings: 0)
    private var controller: SyncController?

    override func spec() {

        beforeEach {
            self.controller = nil
        }

        let performActionsTest: ActionTest = { initialActions, requestResult, performCheck in
            let handler = TestHandler()
            let controller = SyncController(userId: self.userId, handler: handler)

            handler.requestResult = requestResult

            controller.start(with: initialActions, finishedAction: { result in
                switch result {
                case .success(let data):
                    performCheck(data.0)
                case .failure: break
                }
            })

            return controller
        }

        let performErrorTest: ErrorTest = { initialActions, requestResult, performCheck in
            let handler = TestHandler()
            let controller = SyncController(userId: self.userId, handler: handler)

            handler.requestResult = requestResult

            controller.start(with: initialActions, finishedAction: { result in
                switch result {
                case .success: break
                case .failure(let error):
                    performCheck(error)
                }
            })

            return controller
        }

        context("action processing") {
            it("processes store version action") {
                let initial: [QueueAction] = [.storeVersion(3, .group(SyncControllerSpec.groupId), .collection)]
                let expected: [QueueAction] = initial
                var all: [QueueAction]?

                self.controller = performActionsTest(initial, { _ in
                    return Single.just(())
                }, { result in
                    all = result
                })

                expect(all).toEventually(equal(expected))
            }

            it("processes download object action") {
                let action = ObjectBatch(order: 0, library: .user(self.userId), object: .group, keys: [1], version: 0)
                let initial: [QueueAction] = [.syncBatchToFile(action)]
                let expected: [QueueAction] = initial
                var all: [QueueAction]?

                self.controller = performActionsTest(initial, { _ in
                    return Single.just(())
                }, { result in
                    all = result
                })

                expect(all).toEventually(equal(expected))
            }

            it("processes sync download action") {
                let action = ObjectBatch(order: 0, library: .user(self.userId), object: .group, keys: [1], version: 0)
                let initial: [QueueAction] = [.syncBatchToDb(action)]
                let expected: [QueueAction] = initial
                var all: [QueueAction]?

                self.controller = performActionsTest(initial, { _ in
                    return Single.just(())
                }, { result in
                    all = result
                })

                expect(all).toEventually(equal(expected))
            }

            it("processes sync versions (collection) action") {
                SyncControllerSpec.syncVersionData = (3, 35)

                let keys1 = (0..<5).map({ $0.description })
                let keys2 = (5..<15).map({ $0.description })
                let keys3 = (15..<35).map({ $0.description })
                let initial: [QueueAction] = [.syncVersions(.user(self.userId), .collection, 2)]
                let expected: [QueueAction] = [.syncVersions(.user(self.userId), .collection, 2),
                                               .syncBatchToFile(ObjectBatch(order: 0, library: .user(self.userId),
                                                                              object: .collection,
                                                                              keys: keys1,
                                                                              version: 3)),
                                               .syncBatchToDb(ObjectBatch(order: 0, library: .user(self.userId),
                                                                          object: .collection,
                                                                          keys: keys1,
                                                                          version: 3)),
                                               .syncBatchToFile(ObjectBatch(order: 1, library: .user(self.userId),
                                                                            object: .collection,
                                                                            keys: keys2,
                                                                            version: 3)),
                                               .syncBatchToDb(ObjectBatch(order: 1, library: .user(self.userId),
                                                                          object: .collection,
                                                                          keys: keys2,
                                                                          version: 3)),
                                               .syncBatchToFile(ObjectBatch(order: 2, library: .user(self.userId),
                                                                            object: .collection,
                                                                            keys: keys3,
                                                                            version: 3)),
                                               .syncBatchToDb(ObjectBatch(order: 2, library: .user(self.userId),
                                                                          object: .collection,
                                                                          keys: keys3,
                                                                          version: 3)),
                                               .storeVersion(3, .user(self.userId), .collection)]
                var all: [QueueAction]?

                self.controller = performActionsTest(initial, { _ in
                    return Single.just(())
                }, { result in
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

                self.controller = performActionsTest(initial, { _ in
                    return Single.just(())
                }, { result in
                    all = result
                })

                expect(all).toEventually(equal(expected))
            }

            it("processes sync versions (group) action") {
                SyncControllerSpec.syncVersionData = (7, 1)
                SyncControllerSpec.groupIdVersions = Versions(collections: 4, items: 4, trash: 2, searches: 2,
                                                              deletions: 4, settings: 4)

                let groupId = SyncControllerSpec.groupId
                let initial: [QueueAction] = [.syncVersions(.user(self.userId), .group, nil)]
                let expected: [QueueAction] = [.syncVersions(.user(self.userId), .group, nil),
                                               .syncBatchToFile(ObjectBatch(order: 0, library: .user(self.userId),
                                                                              object: .group,
                                                                              keys: [0],
                                                                              version: 7)),
                                               .syncBatchToDb(ObjectBatch(order: 0, library: .user(self.userId),
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

                self.controller = performActionsTest(initial, { _ in
                    return Single.just(())
                }, { result in
                    all = result
                })

                expect(all).toEventually(equal(expected))
            }
        }

        context("fatal error handling") {
            it("doesn't process store version action") {
                let initial: [QueueAction] = [.storeVersion(1, .user(self.userId), .group)]
                var error: SyncError?

                self.controller = performErrorTest(initial, { action in
                    switch action {
                    case .storeVersion:
                        return Single.error(TestErrors.fatal)
                    default:
                        return Single.just(())
                    }
                }, { result in
                    error = result as? SyncError
                })

                expect(error).toEventually(equal(SyncError.noInternetConnection))
            }

            it("doesn't process download object action") {
                let action = ObjectBatch(order: 0, library: .user(self.userId), object: .group, keys: [1], version: 0)
                let initial: [QueueAction] = [.syncBatchToFile(action)]
                var error: SyncError?

                self.controller = performErrorTest(initial, { action in
                    switch action {
                    case .downloadObject(let object):
                        if object == .group {
                            return Single.error(TestErrors.fatal)
                        }
                        return Single.just(())
                    default:
                        return Single.just(())
                    }
                }, { result in
                    error = result as? SyncError
                })

                expect(error).toEventually(equal(SyncError.noInternetConnection))
            }

            it("doesn't process sync download action") {
                let action = ObjectBatch(order: 0, library: .user(self.userId), object: .group, keys: [1], version: 0)
                let initial: [QueueAction] = [.syncBatchToDb(action)]
                var error: SyncError?

                self.controller = performErrorTest(initial, { action in
                    switch action {
                    case .storeObject(let object):
                        if object == .group {
                            return Single.error(TestErrors.fatal)
                        }
                        return Single.just(())
                    default:
                        return Single.just(())
                    }
                }, { result in
                    error = result as? SyncError
                })

                expect(error).toEventually(equal(SyncError.noInternetConnection))
            }

            it("doesn't process sync versions (collection) action") {
                SyncControllerSpec.syncVersionData = (7, 1)

                let initial: [QueueAction] = [.syncVersions(.user(self.userId), .collection, 1)]
                var error: SyncError?

                self.controller = performErrorTest(initial, { action in
                    switch action {
                    case .syncVersions(let object):
                        if object == .collection {
                            return Single.error(TestErrors.fatal)
                        }
                        return Single.just(())
                    default:
                        return Single.just(())
                    }
                }, { result in
                    error = result as? SyncError
                })

                expect(error).toEventually(equal(SyncError.noInternetConnection))
            }

            it("doesn't process create groups action") {
                SyncControllerSpec.syncVersionData = (7, 1)

                let initial: [QueueAction] = [.createLibraryActions]
                var error: SyncError?

                self.controller = performErrorTest(initial, { action in
                    switch action {
                    case .loadGroups:
                        return Single.error(TestErrors.fatal)
                    default:
                        return Single.just(())
                    }
                }, { result in
                    error = result as? SyncError
                })

                expect(error).toEventually(equal(SyncError.allLibrariesFetchFailed(SyncError.noInternetConnection)))
            }
        }

        context("non-fatal error handling") {
            it("doesn't abort") {
                SyncControllerSpec.syncVersionData = (7, 1)
                SyncControllerSpec.groupIdVersions = Versions(collections: 4, items: 4, trash: 2, searches: 2,
                                                              deletions: 0, settings: 0)

                let initial: [QueueAction] = [.syncVersions(.user(self.userId), .group, nil)]
                var didFinish: Bool?

                self.controller = performActionsTest(initial, { action in
                    switch action {
                    case .syncVersions(let object):
                        if object == .collection {
                            return Single.error(SyncActionHandlerError.expired)
                        }
                    default: break
                    }
                    return Single.just(())
                }, { result in
                    didFinish = true
                })

                expect(didFinish).toEventually(beTrue())
            }
        }
    }
}
