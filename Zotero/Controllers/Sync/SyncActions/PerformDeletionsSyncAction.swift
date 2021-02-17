//
//  PerformDeletionsSyncAction.swift
//  Zotero
//
//  Created by Michal Rentka on 09.02.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RxSwift

struct PerformDeletionsSyncAction: SyncAction {
    typealias Result = [(String, String)]

    let libraryId: LibraryIdentifier
    let collections: [String]
    let items: [String]
    let searches: [String]
    let tags: [String]
    let ignoreConflicts: Bool

    unowned let dbStorage: DbStorage

    var result: Single<[(String, String)]> {
        return Single.create { subscriber -> Disposable in
            do {
                let request = PerformDeletionsDbRequest(libraryId: self.libraryId, collections: self.collections, items: self.items, searches: self.searches, tags: self.tags, ignoreConflicts: self.ignoreConflicts)
                let conflicts = try self.dbStorage.createCoordinator().perform(request: request)
                subscriber(.success(conflicts))
            } catch let error {
                subscriber(.error(error))
            }

            return Disposables.create()
        }
    }
}
