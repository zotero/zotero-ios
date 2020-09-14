//
//  SyncDeletionsSyncAction.swift
//  Zotero
//
//  Created by Michal Rentka on 30/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RxSwift

struct SyncDeletionsSyncAction: SyncAction {
    typealias Result = [String]

    let currentVersion: Int?
    let sinceVersion: Int
    let libraryId: LibraryIdentifier
    let userId: Int

    unowned let apiClient: ApiClient
    unowned let dbStorage: DbStorage
    let queue: DispatchQueue
    let scheduler: SchedulerType

    var result: Single<[String]> {
        return self.apiClient.send(request: DeletionsRequest(libraryId: libraryId, userId: userId, version: sinceVersion),
                                   queue: self.queue)
                             .observeOn(self.scheduler)
                             .flatMap { (response: DeletionsResponse, headers) in
                                 let newVersion = headers.lastModifiedVersion

                                 if let version = self.currentVersion, version != newVersion {
                                     return Single.error(SyncError.NonFatal.versionMismatch)
                                 }

                                 do {
                                     let request = PerformDeletionsDbRequest(libraryId: self.libraryId, response: response, version: newVersion)
                                     let conflicts = try self.dbStorage.createCoordinator().perform(request: request)
                                     return Single.just(conflicts)
                                 } catch let error {
                                     return Single.error(error)
                                 }
                             }
    }
}
