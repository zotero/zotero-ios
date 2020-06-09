//
//  SyncVersionsSyncAction.swift
//  Zotero
//
//  Created by Michal Rentka on 30/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjack
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

    unowned let apiClient: ApiClient
    unowned let dbStorage: DbStorage
    let queue: DispatchQueue
    let scheduler: SchedulerType

    var result: Single<(Int, [String])> {
        switch object {
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

    private func synchronizeVersions<Obj: SyncableObject>(for: Obj.Type, libraryId: LibraryIdentifier, userId: Int,
                                                          object: SyncObject, since sinceVersion: Int?,
                                                          current currentVersion: Int?,
                                                          syncType: SyncController.SyncType) -> Single<(Int, [String])> {
        let forcedSinceVersion = syncType == .all ? nil : sinceVersion
        let request = VersionsRequest(libraryId: libraryId, userId: userId, objectType: object, version: forcedSinceVersion)
        return self.apiClient.send(request: request, queue: self.queue)
                             .observeOn(self.scheduler)
                             .flatMap { (response: [String: Int], headers) -> Single<(Int, [String])> in
                                  let newVersion = headers.lastModifiedVersion

                                  if let current = currentVersion, newVersion != current {
                                      return Single.error(SyncError.versionMismatch)
                                  }

                                  var isTrash: Bool?
                                  switch object {
                                  case .item:
                                      isTrash = false
                                  case .trash:
                                      isTrash = true
                                  default: break
                                  }

                                  let request = SyncVersionsDbRequest<Obj>(versions: response,
                                                                           libraryId: libraryId,
                                                                           isTrash: isTrash,
                                                                           syncType: syncType,
                                                                           delayIntervals: self.syncDelayIntervals)
                                  do {
                                      let identifiers = try self.dbStorage.createCoordinator().perform(request: request)
                                      return Single.just((newVersion, identifiers))
                                  } catch let error {
                                      return Single.error(error)
                                  }
                             }
    }
}
