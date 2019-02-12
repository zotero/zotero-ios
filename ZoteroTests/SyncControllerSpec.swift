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
    case storeVersion(SyncGroupType)
    case markResync(SyncObjectType)
}

fileprivate class TestHandler: SyncActionHandler {
    var requestResult: ((TestAction) -> Single<()>)?

    private func result(for action: TestAction) -> Single<()> {
        return self.requestResult?(action) ?? Single.just(())
    }

    func loadAllGroupIdsAndVersions() -> PrimitiveSequence<SingleTrait, Array<(Int, Versions)>> {
        return self.result(for: .loadGroups).flatMap {
            return Single.just([(SyncControllerSpec.groupId, SyncControllerSpec.groupIdVersions)])
        }
    }

    func synchronizeVersions(for group: SyncGroupType, object: SyncObjectType, since sinceVersion: Int?,
                             current currentVersion: Int?) -> PrimitiveSequence<SingleTrait, (Int, Array<Any>)> {
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

    func downloadObjectJson(for keys: String, group: SyncGroupType,
                            object: SyncObjectType, version: Int, index: Int) -> Completable {
        return self.result(for: .downloadObject(object)).asCompletable()
    }

    func markForResync(keys: [Any], object: SyncObjectType) -> Completable {
        return self.result(for: .markResync(object)).asCompletable()
    }

    func synchronizeDbWithFetchedFiles(group: SyncGroupType, object: SyncObjectType,
                                       version: Int, index: Int) -> Completable {
        return self.result(for: .storeObject(object)).asCompletable()
    }

    func storeVersion(_ version: Int, for group: SyncGroupType, object: SyncObjectType) -> Completable {
        return self.result(for: .storeVersion(.group(SyncControllerSpec.groupId))).asCompletable()
    }
}

fileprivate typealias ActionTest = ([QueueAction], @escaping (TestAction) -> Single<()>,
                                    @escaping ([QueueAction]) -> Void) -> SyncController
fileprivate typealias ErrorTest = ([QueueAction], @escaping (TestAction) -> Single<()>,
                                   @escaping (Error) -> Void) -> SyncController

class SyncControllerSpec: QuickSpec {
    fileprivate static let groupId = 10
    private let userId = 100

    fileprivate static var syncVersionData: (Int, Int) = (0, 0)
    fileprivate static var groupIdVersions: Versions = Versions(collections: 0, items: 0, trash: 0, searches: 0)
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
                let action = ObjectAction(order: 0, group: .user(self.userId), object: .group, keys: [1], version: 0)
                let initial: [QueueAction] = [.syncObjectToFile(action)]
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
                let action = ObjectAction(order: 0, group: .user(self.userId), object: .group, keys: [1], version: 0)
                let initial: [QueueAction] = [.syncObjectToDb(action)]
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
                SyncControllerSpec.syncVersionData = (3, 70)

                let keys1 = (0..<50).map({ $0.description })
                let keys2 = (50..<70).map({ $0.description })
                let initial: [QueueAction] = [.syncVersions(.user(self.userId), .collection, 2)]
                let expected: [QueueAction] = [.syncVersions(.user(self.userId), .collection, 2),
                                               .syncObjectToFile(ObjectAction(order: 0, group: .user(self.userId),
                                                                              object: .collection,
                                                                              keys: keys1,
                                                                              version: 3)),
                                               .syncObjectToFile(ObjectAction(order: 1, group: .user(self.userId),
                                                                              object: .collection,
                                                                              keys: keys2,
                                                                              version: 3)),
                                               .syncObjectToDb(ObjectAction(order: 0, group: .user(self.userId),
                                                                            object: .collection,
                                                                            keys: keys1,
                                                                            version: 3)),
                                               .syncObjectToDb(ObjectAction(order: 1, group: .user(self.userId),
                                                                            object: .collection,
                                                                            keys: keys2,
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
                SyncControllerSpec.groupIdVersions = Versions(collections: 2, items: 1, trash: 1, searches: 1)

                let groupId = SyncControllerSpec.groupId
                let initial: [QueueAction] = [.createGroupActions]
                let expected: [QueueAction] = [.createGroupActions,
                                               .syncVersions(.group(groupId), .collection, 2),
                                               .syncObjectToFile(ObjectAction(order: 0, group: .group(groupId),
                                                                              object: .collection,
                                                                              keys: ["0"],
                                                                              version: 3)),
                                               .syncObjectToDb(ObjectAction(order: 0, group: .group(groupId),
                                                                            object: .collection,
                                                                            keys: ["0"],
                                                                            version: 3)),
                                               .storeVersion(3, .group(groupId), .collection),
                                               .syncVersions(.group(groupId), .item, 1),
                                               .syncObjectToFile(ObjectAction(order: 0, group: .group(groupId),
                                                                              object: .item,
                                                                              keys: ["0"],
                                                                              version: 3)),
                                               .syncObjectToDb(ObjectAction(order: 0, group: .group(groupId),
                                                                            object: .item,
                                                                            keys: ["0"],
                                                                            version: 3)),
                                               .storeVersion(3, .group(groupId), .item),
                                               .syncVersions(.group(groupId), .trash, 1),
                                               .syncObjectToFile(ObjectAction(order: 0, group: .group(groupId),
                                                                              object: .trash,
                                                                              keys: ["0"],
                                                                              version: 3)),
                                               .syncObjectToDb(ObjectAction(order: 0, group: .group(groupId),
                                                                            object: .trash,
                                                                            keys: ["0"],
                                                                            version: 3)),
                                               .storeVersion(3, .group(groupId), .trash),
                                               .syncVersions(.group(groupId), .search, 1),
                                               .syncObjectToFile(ObjectAction(order: 0, group: .group(groupId),
                                                                              object: .search,
                                                                              keys: ["0"],
                                                                              version: 3)),
                                               .syncObjectToDb(ObjectAction(order: 0, group: .group(groupId),
                                                                            object: .search,
                                                                            keys: ["0"],
                                                                            version: 3)),
                                               .storeVersion(3, .group(groupId), .search)]
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
                SyncControllerSpec.groupIdVersions = Versions(collections: 4, items: 4, trash: 2, searches: 2)

                let groupId = SyncControllerSpec.groupId
                let initial: [QueueAction] = [.syncVersions(.user(self.userId), .group, nil)]
                let expected: [QueueAction] = [.syncVersions(.user(self.userId), .group, nil),
                                               .syncObjectToFile(ObjectAction(order: 0, group: .user(self.userId),
                                                                              object: .group,
                                                                              keys: [0],
                                                                              version: 7)),
                                               .syncObjectToDb(ObjectAction(order: 0, group: .user(self.userId),
                                                                            object: .group,
                                                                            keys: [0],
                                                                            version: 7)),
                                               .createGroupActions,
                                               .syncVersions(.group(groupId), .collection, 4),
                                               .syncObjectToFile(ObjectAction(order: 0, group: .group(groupId),
                                                                              object: .collection,
                                                                              keys: ["0"],
                                                                              version: 7)),
                                               .syncObjectToDb(ObjectAction(order: 0, group: .group(groupId),
                                                                            object: .collection,
                                                                            keys: ["0"],
                                                                            version: 7)),
                                               .storeVersion(7, .group(groupId), .collection),
                                               .syncVersions(.group(groupId), .item, 4),
                                               .syncObjectToFile(ObjectAction(order: 0, group: .group(groupId),
                                                                              object: .item,
                                                                              keys: ["0"],
                                                                              version: 7)),
                                               .syncObjectToDb(ObjectAction(order: 0, group: .group(groupId),
                                                                            object: .item,
                                                                            keys: ["0"],
                                                                            version: 7)),
                                               .storeVersion(7, .group(groupId), .item),
                                               .syncVersions(.group(groupId), .trash, 2),
                                               .syncObjectToFile(ObjectAction(order: 0, group: .group(groupId),
                                                                              object: .trash,
                                                                              keys: ["0"],
                                                                              version: 7)),
                                               .syncObjectToDb(ObjectAction(order: 0, group: .group(groupId),
                                                                            object: .trash,
                                                                            keys: ["0"],
                                                                            version: 7)),
                                               .storeVersion(7, .group(groupId), .trash),
                                               .syncVersions(.group(groupId), .search, 2),
                                               .syncObjectToFile(ObjectAction(order: 0, group: .group(groupId),
                                                                              object: .search,
                                                                              keys: ["0"],
                                                                              version: 7)),
                                               .syncObjectToDb(ObjectAction(order: 0, group: .group(groupId),
                                                                            object: .search,
                                                                            keys: ["0"],
                                                                            version: 7)),
                                               .storeVersion(7, .group(groupId), .search)]
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
                let action = ObjectAction(order: 0, group: .user(self.userId), object: .group, keys: [1], version: 0)
                let initial: [QueueAction] = [.syncObjectToFile(action)]
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
                let action = ObjectAction(order: 0, group: .user(self.userId), object: .group, keys: [1], version: 0)
                let initial: [QueueAction] = [.syncObjectToDb(action)]
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

                let initial: [QueueAction] = [.createGroupActions]
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

                expect(error).toEventually(equal(SyncError.allGroupsFetchFailed(SyncError.noInternetConnection)))
            }
        }

        context("non-fatal error handling") {
            it("doesn't abort") {
                SyncControllerSpec.syncVersionData = (7, 1)
                SyncControllerSpec.groupIdVersions = Versions(collections: 4, items: 4, trash: 2, searches: 2)

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
