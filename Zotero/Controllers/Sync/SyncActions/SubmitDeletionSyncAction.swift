//
//  SubmitDeletionSyncAction.swift
//  Zotero
//
//  Created by Michal Rentka on 30/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RxSwift

struct SubmitDeletionSyncAction: SyncAction {
    typealias Result = Int

    let keys: [String]
    let object: SyncObject
    let version: Int
    let libraryId: LibraryIdentifier
    let userId: Int

    unowned let apiClient: ApiClient
    unowned let dbStorage: DbStorage
    let queue: DispatchQueue
    let scheduler: SchedulerType

    var result: Single<Int> {
        let request = SubmitDeletionsRequest(libraryId: self.libraryId, userId: self.userId,
                                             objectType: self.object, keys: self.keys, version: self.version)
        return self.apiClient.send(request: request, queue: self.queue)
                             .observeOn(self.scheduler)
                             .flatMap({ _, headers -> Single<Int> in
                                do {
                                    let coordinator = try self.dbStorage.createCoordinator()

                                    switch self.object {
                                    case .collection:
                                        let request = DeleteObjectsDbRequest<RCollection>(keys: self.keys, libraryId: self.libraryId)
                                        try coordinator.perform(request: request)
                                    case .item, .trash:
                                        let request = DeleteObjectsDbRequest<RItem>(keys: self.keys, libraryId: self.libraryId)
                                        try coordinator.perform(request: request)
                                    case .search:
                                        let request = DeleteObjectsDbRequest<RSearch>(keys: self.keys, libraryId: self.libraryId)
                                        try coordinator.perform(request: request)
                                    case .settings: break
                                    }

                                    let newVersion = headers.lastModifiedVersion
                                    let updateVersion = UpdateVersionsDbRequest(version: newVersion, libraryId: self.libraryId, type: .object(self.object))
                                    try coordinator.perform(request: updateVersion)

                                    return Single.just(newVersion)
                                } catch let error {
                                    return Single.error(error)
                                }
                             })
    }
}
