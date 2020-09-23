//
//  SyncVersionsSyncAction.swift
//  Zotero
//
//  Created by Michal Rentka on 30/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxSwift

struct SyncVersionsSyncAction: SyncAction {
    typealias Result = (Int, [String])

    let object: SyncObject
    let sinceVersion: Int?
    let currentVersion: Int?
    let syncType: SyncController.SyncType
    let libraryId: LibraryIdentifier
    let userId: Int
    let syncDelayIntervals: [Double]
    let checkRemote: Bool

    private var isTrash: Bool? {
        switch self.object {
        case .item: return false
        case .trash: return true
        default: return nil
        }
    }

    unowned let apiClient: ApiClient
    unowned let dbStorage: DbStorage
    let queue: DispatchQueue
    let scheduler: SchedulerType

    var result: Single<(Int, [String])> {
        switch self.object {
        case .collection:
            return self.synchronizeVersions(for: RCollection.self, libraryId: self.libraryId, userId: self.userId, object: self.object,
                                            since: self.sinceVersion, current: self.currentVersion, syncType: self.syncType)
        case .item, .trash:
            return self.synchronizeVersions(for: RItem.self, libraryId: self.libraryId, userId: self.userId, object: self.object,
                                            since: self.sinceVersion, current: self.currentVersion, syncType: self.syncType)
        case .search:
            return self.synchronizeVersions(for: RSearch.self, libraryId: self.libraryId, userId: self.userId, object: self.object,
                                            since: self.sinceVersion, current: self.currentVersion, syncType: self.syncType)
        }
    }

    private func synchronizeVersions<Obj: SyncableObject>(for type: Obj.Type, libraryId: LibraryIdentifier, userId: Int,
                                                          object: SyncObject, since sinceVersion: Int?,
                                                          current currentVersion: Int?,
                                                          syncType: SyncController.SyncType) -> Single<(Int, [String])> {
        if !self.checkRemote {
            return self.loadChangedObjects(for: type, from: [:], in: libraryId, syncType: syncType, newVersion: (currentVersion ?? 0),
                                           delayIntervals: self.syncDelayIntervals)
                       .observeOn(self.scheduler)
        }

        return self.loadRemoteVersions(for: object, in: libraryId, userId: userId, since: sinceVersion, syncType: syncType)
                   .observeOn(self.scheduler)
            .flatMap { (response: [String: Int], headers) -> Single<(Int, [String])> in
                let newVersion = headers.lastModifiedVersion

                if let current = currentVersion, newVersion != current {
                    return Single.error(SyncError.NonFatal.versionMismatch)
                }

                return self.loadChangedObjects(for: type, from: response, in: libraryId, syncType: syncType, newVersion: newVersion,
                                               delayIntervals: self.syncDelayIntervals)
            }
    }

    private func loadRemoteVersions(for object: SyncObject, in libraryId: LibraryIdentifier, userId: Int, since sinceVersion: Int?, syncType: SyncController.SyncType) -> Single<([String: Int], ResponseHeaders)> {
        let forcedSinceVersion = syncType == .all ? nil : sinceVersion
        let request = VersionsRequest(libraryId: libraryId, userId: userId, objectType: object, version: forcedSinceVersion)
        return self.apiClient.send(request: request, queue: self.queue)
    }

    private func loadChangedObjects<Obj: SyncableObject>(for type: Obj.Type, from response: [String: Int], in libraryId: LibraryIdentifier,
                                                         syncType: SyncController.SyncType, newVersion: Int,
                                                         delayIntervals: [Double]) -> Single<(Int, [String])> {
        return Single.create { subscriber -> Disposable in
            let request = SyncVersionsDbRequest<Obj>(versions: response, libraryId: libraryId, isTrash: isTrash,
                                                     syncType: syncType, delayIntervals: delayIntervals)
            do {
                let identifiers = try self.dbStorage.createCoordinator().perform(request: request)
                subscriber(.success((newVersion, identifiers)))
            } catch let error {
                subscriber(.error(error))
            }

            return Disposables.create()
        }
    }
}
