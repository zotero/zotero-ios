//
//  StoreVersionSyncAction.swift
//  Zotero
//
//  Created by Michal Rentka on 30/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RxSwift

struct StoreVersionSyncAction: SyncAction {
    typealias Result = ()

    let version: Int
    let type: UpdateVersionType
    let libraryId: LibraryIdentifier

    unowned let dbStorage: DbStorage

    var result: Single<()> {
        return Single.create { subscriber -> Disposable in
            do {
                let request = UpdateVersionsDbRequest(version: self.version, libraryId: self.libraryId, type: self.type)
                try self.dbStorage.createCoordinator().perform(request: request)
                subscriber(.success(()))
            } catch let error {
                subscriber(.error(error))
            }
            return Disposables.create()
        }
    }
}
