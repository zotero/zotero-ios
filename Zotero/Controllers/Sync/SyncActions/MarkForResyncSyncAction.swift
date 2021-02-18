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

    let keys: [Any]
    let object: SyncObject
    let libraryId: LibraryIdentifier

    unowned let dbStorage: DbStorage

    var result: Single<()> {
        return Single.create { subscriber -> Disposable in
            do {
                switch self.object {
                case .collection:
                    let request = try MarkForResyncDbAction<RCollection>(libraryId: self.libraryId, keys: self.keys)
                    try self.dbStorage.createCoordinator().perform(request: request)
                case .item, .trash:
                    let request = try MarkForResyncDbAction<RItem>(libraryId: self.libraryId, keys: self.keys)
                    try self.dbStorage.createCoordinator().perform(request: request)
                case .search:
                    let request = try MarkForResyncDbAction<RSearch>(libraryId: self.libraryId, keys: self.keys)
                    try self.dbStorage.createCoordinator().perform(request: request)
                case .settings:
                    let request = try MarkForResyncDbAction<RPageIndex>(libraryId: self.libraryId, keys: self.keys)
                    try self.dbStorage.createCoordinator().perform(request: request)
                }
                subscriber(.success(()))
            } catch let error {
                subscriber(.error(error))
            }
            return Disposables.create()
        }
    }
}
