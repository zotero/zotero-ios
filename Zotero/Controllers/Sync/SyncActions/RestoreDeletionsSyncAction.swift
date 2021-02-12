//
//  RestoreDeletionsSyncAction.swift
//  Zotero
//
//  Created by Michal Rentka on 11.02.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RxSwift

struct RestoreDeletionsSyncAction: SyncAction {
    typealias Result = ()

    let libraryId: LibraryIdentifier
    let collections: [String]
    let items: [String]

    unowned let dbStorage: DbStorage

    var result: Single<()> {
        return Single.create { subscriber -> Disposable in
            do {
                let request = MarkObjectsAsChangedByUser(libraryId: self.libraryId, collections: self.collections, items: self.items)
                try self.dbStorage.createCoordinator().perform(request: request)
                subscriber(.success(()))
            } catch let error {
                subscriber(.error(error))
            }

            return Disposables.create()
        }
    }
}
