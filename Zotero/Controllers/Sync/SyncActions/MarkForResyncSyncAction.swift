//
//  MarkForResyncSyncAction.swift
//  Zotero
//
//  Created by Michal Rentka on 30/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjack
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
                case .group:
                    let request = try MarkGroupForResyncDbAction(identifiers: self.keys)
                    try self.dbStorage.createCoordinator().perform(request: request)
                case .collection:
                    let request = try MarkForResyncDbAction<RCollection>(libraryId: self.libraryId, keys: self.keys)
                    try self.dbStorage.createCoordinator().perform(request: request)
                case .item, .trash:
                    let request = try MarkForResyncDbAction<RItem>(libraryId: self.libraryId, keys: self.keys)
                    try self.dbStorage.createCoordinator().perform(request: request)
                case .search:
                    let request = try MarkForResyncDbAction<RSearch>(libraryId: self.libraryId, keys: self.keys)
                    try self.dbStorage.createCoordinator().perform(request: request)
                case .tag: // Tags are not synchronized, this should not be called
                    DDLogError("SyncActionHandler: markForResync tried to sync tags")
                    break
                }
                subscriber(.success(()))
            } catch let error {
                subscriber(.error(error))
            }
            return Disposables.create()
        }
    }
}
