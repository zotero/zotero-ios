//
//  MarkChangesAsResolvedSyncAction.swift
//  Zotero
//
//  Created by Michal Rentka on 30/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RxSwift

struct MarkChangesAsResolvedSyncAction: SyncAction {
    typealias Result = ()

    let libraryId: LibraryIdentifier

    unowned let dbStorage: DbStorage
    let queue: DispatchQueue

    var result: Single<()> {
        return Single.create { subscriber -> Disposable in
            do {
                let request = MarkAllLibraryObjectChangesAsSyncedDbRequest(libraryId: self.libraryId)
                try self.dbStorage.perform(request: request, on: self.queue)
                subscriber(.success(()))
            } catch let error {
                subscriber(.failure(error))
            }
            return Disposables.create()
        }
    }
}
