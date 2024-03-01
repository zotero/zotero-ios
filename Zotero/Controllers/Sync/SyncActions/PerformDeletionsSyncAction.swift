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
    typealias Result = ([PerformDeletionsDbRequest.DeletedItem], [PerformDeletionsDbRequest.Conflict])

    let libraryId: LibraryIdentifier
    let collections: [String]
    let items: [String]
    let searches: [String]
    let tags: [String]
    let conflictMode: PerformDeletionsDbRequest.ConflictResolutionMode

    unowned let dbStorage: DbStorage
    let queue: DispatchQueue

    var result: Single<([PerformDeletionsDbRequest.DeletedItem], [PerformDeletionsDbRequest.Conflict])> {
        return Single.create { subscriber -> Disposable in
            do {
                let request = PerformDeletionsDbRequest(
                    libraryId: libraryId,
                    collections: collections,
                    items: items,
                    searches: searches,
                    tags: tags,
                    conflictMode: conflictMode
                )
                let response = try dbStorage.perform(request: request, on: queue, invalidateRealm: true)
                subscriber(.success(response))
            } catch let error {
                subscriber(.failure(error))
            }
            return Disposables.create()
        }
    }
}
