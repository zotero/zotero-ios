//
//  MarkForResyncSyncAction.swift
//  Zotero
//
//  Created by Michal Rentka on 30/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxSwift

struct MarkForResyncSyncAction: SyncAction {
    typealias Result = ()

    let keys: [String]
    let object: SyncObject
    let libraryId: LibraryIdentifier

    unowned let dbStorage: DbStorage

    var result: Single<()> {
        return Single.create { subscriber -> Disposable in
            do {
                let request: DbRequest
                switch self.object {
                case .collection:
                    request = MarkForResyncDbAction<RCollection>(libraryId: self.libraryId, keys: self.keys)
                case .item, .trash:
                    request = MarkForResyncDbAction<RItem>(libraryId: self.libraryId, keys: self.keys)
                case .search:
                    request = MarkForResyncDbAction<RSearch>(libraryId: self.libraryId, keys: self.keys)
                case .settings:
                    request = MarkForResyncDbAction<RPageIndex>(libraryId: self.libraryId, keys: self.keys)
                }
                try self.dbStorage.perform(request: request)
                subscriber(.success(()))
            } catch let error {
                subscriber(.failure(error))
            }
            return Disposables.create()
        }
    }
}
