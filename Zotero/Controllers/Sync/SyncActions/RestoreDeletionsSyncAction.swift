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
    let queue: DispatchQueue

    var result: Single<()> {
        return Single.create { subscriber -> Disposable in
            do {
                let request = MarkObjectsAsChangedByUser(libraryId: self.libraryId, collections: self.collections, items: self.items)
                try self.dbStorage.perform(request: request, on: self.queue)
                subscriber(.success(()))
            } catch let error {
                subscriber(.failure(error))
            }

            return Disposables.create()
        }
    }
}
