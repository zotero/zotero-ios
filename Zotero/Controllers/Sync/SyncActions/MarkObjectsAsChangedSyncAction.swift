//
//  MarkObjectsAsChangedSyncAction.swift
//  Zotero
//
//  Created by Michal Rentka on 25.03.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxSwift

struct MarkObjectsAsChangedSyncAction: SyncAction {
    typealias Result = ()

    let keys: [String]
    let object: SyncObject
    let libraryId: LibraryIdentifier
    unowned let dbStorage: DbStorage

    var result: Single<()> {
        do {
            let request: DbRequest

            switch self.object {
            case .collection:
                request = MarkOtherObjectsAsChangedByUser<RCollection>(libraryId: self.libraryId, keys: self.keys)
            case .item:
                request = MarkOtherObjectsAsChangedByUser<RItem>(libraryId: self.libraryId, keys: self.keys)
            case .search:
                request = MarkOtherObjectsAsChangedByUser<RSearch>(libraryId: self.libraryId, keys: self.keys)
            case .settings, .trash:
                DDLogError("MarkObjectsAsChangedSyncAction: tried to mark \(self.object) as changed")
                return Single.just(())
            }

            try self.dbStorage.createCoordinator().perform(request: request)

            return Single.just(())
        } catch let error {
            DDLogError("MarkObjectsAsChangedSyncAction: can't mark objects as changed - \(error)")
            return Single.error(error)
        }
    }
}
