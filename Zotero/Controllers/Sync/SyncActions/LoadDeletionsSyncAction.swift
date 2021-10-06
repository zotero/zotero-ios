//
//  LoadDeletionsSyncAction.swift
//  Zotero
//
//  Created by Michal Rentka on 09.02.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RxSwift

struct LoadDeletionsSyncAction: SyncAction {
    typealias Result = (collections: [String], items: [String], searches: [String], tags: [String], version: Int)

    let currentVersion: Int?
    let sinceVersion: Int
    let libraryId: LibraryIdentifier
    let userId: Int

    unowned let apiClient: ApiClient
    let queue: DispatchQueue
    let scheduler: SchedulerType

    var result: Single<(collections: [String], items: [String], searches: [String], tags: [String], version: Int)> {
        return self.apiClient.send(request: DeletionsRequest(libraryId: self.libraryId, userId: self.userId, version: self.sinceVersion), queue: self.queue)
                             .observe(on: self.scheduler)
                             .flatMap { (decoded: DeletionsResponse, response) in
                                 let newVersion = response.allHeaderFields.lastModifiedVersion

                                 if let version = self.currentVersion, version != newVersion {
                                     return Single.error(SyncError.NonFatal.versionMismatch(self.libraryId))
                                 }

                                 return Single.just((decoded.collections, decoded.items, decoded.searches, decoded.tags, newVersion))
                             }
    }
}
