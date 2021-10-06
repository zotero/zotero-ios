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

    unowned let apiClient: ApiClient
    unowned let dbStorage: DbStorage
    let queue: DispatchQueue
    let scheduler: SchedulerType

    var result: Single<(Int, [String])> {
        switch self.object {
        case .collection:
            return self.synchronizeVersions(for: RCollection.self, libraryId: self.libraryId, userId: self.userId, object: self.object, since: self.sinceVersion, current: self.currentVersion,
                                            syncType: self.syncType)
        case .item:
            return self.synchronizeVersions(for: RItem.self, libraryId: self.libraryId, userId: self.userId, object: self.object, since: self.sinceVersion, current: self.currentVersion,
                                            syncType: self.syncType)
        case .trash:
            return self.synchronizeVersions(for: RItem.self, libraryId: self.libraryId, userId: self.userId, object: self.object, since: self.sinceVersion, current: self.currentVersion,
                                            syncType: self.syncType)
        case .search:
            return self.synchronizeVersions(for: RSearch.self, libraryId: self.libraryId, userId: self.userId, object: self.object, since: self.sinceVersion, current: self.currentVersion,
                                            syncType: self.syncType)
        case .settings:
            return Single.just((0, []))
        }
    }

    private func synchronizeVersions<Obj: SyncableObject & Deletable & Updatable>(for type: Obj.Type, libraryId: LibraryIdentifier, userId: Int, object: SyncObject, since sinceVersion: Int?,
                                                                                  current currentVersion: Int?, syncType: SyncController.SyncType) -> Single<(Int, [String])> {
        if !self.checkRemote && self.syncType != .full {
            return self.loadChangedObjects(for: object, from: [:], in: libraryId, syncType: syncType, newVersion: (currentVersion ?? 0), delayIntervals: self.syncDelayIntervals)
                       .observe(on: self.scheduler)
        }

        return self.loadRemoteVersions(for: object, in: libraryId, userId: userId, since: sinceVersion, syncType: syncType)
                   .observe(on: self.scheduler)
                   .flatMap { (decoded: [String: Int], response) -> Single<(Int, [String])> in
                       let newVersion = response.allHeaderFields.lastModifiedVersion

                       if let current = currentVersion, newVersion != current {
                           return Single.error(SyncError.NonFatal.versionMismatch(libraryId))
                       }

                       return self.loadChangedObjects(for: object, from: decoded, in: libraryId, syncType: syncType, newVersion: newVersion, delayIntervals: self.syncDelayIntervals)
                   }
    }

    private func loadRemoteVersions(for object: SyncObject, in libraryId: LibraryIdentifier, userId: Int, since sinceVersion: Int?, syncType: SyncController.SyncType)
                                                                                                                                                           -> Single<([String: Int], HTTPURLResponse)> {
        let request = VersionsRequest(libraryId: libraryId, userId: userId, objectType: object, version: sinceVersion)
        return self.apiClient.send(request: request, queue: self.queue)
    }

    private func loadChangedObjects(for object: SyncObject, from response: [String: Int], in libraryId: LibraryIdentifier, syncType: SyncController.SyncType, newVersion: Int, delayIntervals: [Double])
                                                                                                                                                                            -> Single<(Int, [String])> {
        let request = SyncVersionsDbRequest(versions: response, libraryId: libraryId, syncObject: object, syncType: syncType, delayIntervals: delayIntervals)

        return Single.create { subscriber -> Disposable in
            do {
                let coordinator = try self.dbStorage.createCoordinator()
                switch syncType {
                case .full:
                    try coordinator.perform(request: MarkOtherObjectsAsChangedByUser(syncObject: object, versions: response, libraryId: libraryId))
                case .collectionsOnly, .ignoreIndividualDelays, .normal: break
                }
                let identifiers = try coordinator.perform(request: request)
                subscriber(.success((newVersion, identifiers)))
            } catch let error {
                subscriber(.failure(error))
            }

            return Disposables.create()
        }
    }
}
