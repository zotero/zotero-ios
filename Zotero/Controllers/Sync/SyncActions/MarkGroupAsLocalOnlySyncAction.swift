//
//  MarkGroupAsLocalOnlySyncAction.swift
//  Zotero
//
//  Created by Michal Rentka on 30/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RxSwift

struct MarkGroupAsLocalOnlySyncAction: SyncAction {
    typealias Result = ()

    let groupId: Int

    unowned let dbStorage: DbStorage

    var result: Single<()> {
        return Single.create { subscriber -> Disposable in
            do {
                let request = MarkGroupAsLocalOnlyDbRequest(groupId: self.groupId)
                try self.dbStorage.perform(request: request)
                subscriber(.success(()))
            } catch let error {
                subscriber(.failure(error))
            }
            return Disposables.create()
        }
    }
}
