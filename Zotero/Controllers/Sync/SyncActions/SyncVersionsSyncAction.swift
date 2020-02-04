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
    typealias Result = (Int, [Any])

    let object: SyncObject
    let sinceVersion: Int?
    let currentVersion: Int?
    let syncType: SyncController.SyncType
    let libraryId: LibraryIdentifier
    let userId: Int
    let syncDelayIntervals: [Double]

    unowned let apiClient: ApiClient
    unowned let dbStorage: DbStorage

    var result: Single<(Int, [Any])> {
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
        case .group:
            DDLogError("SyncVersionsSyncAction: tried to sync group type")
            return Single.just((0, []))
        case .tag: // Tags are not synchronized, this should not be called
            DDLogError("SyncVersionsSyncAction: tried to sync tags type")
            return Single.just((0, []))
        }
    }

    private func synchronizeVersions<Obj: SyncableObject>(for: Obj.Type, libraryId: LibraryIdentifier, userId: Int,
                                                          object: SyncObject, since sinceVersion: Int?,
                                                          current currentVersion: Int?,
                                                          syncType: SyncController.SyncType) -> Single<(Int, [Any])> {
        let forcedSinceVersion = syncType == .all ? nil : sinceVersion
        let request = VersionsRequest<String>(libraryId: libraryId, userId: userId, objectType: object, version: forcedSinceVersion)
        return self.apiClient.send(request: request)
                             .flatMap { (response: [String: Int], headers) -> Single<(Int, [Any])> in
                                  let newVersion = self.lastVersion(from: headers)

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

    private func lastVersion(from headers: ResponseHeaders) -> Int {
        // Workaround for broken headers (stored in case-sensitive dictionary) on iOS
        let lowercase = headers["last-modified-version"] as? String
        let uppercase = headers["Last-Modified-Version"] as? String
        return (lowercase ?? uppercase).flatMap(Int.init) ?? 0
    }
}
