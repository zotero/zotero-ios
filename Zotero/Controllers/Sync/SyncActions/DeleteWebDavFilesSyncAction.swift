//
//  DeleteWebDavFilesSyncAction.swift
//  Zotero
//
//  Created by Michal Rentka on 29.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxSwift

struct DeleteWebDavFilesSyncAction: SyncAction {
    typealias Result = Set<String>

    let libraryId: LibraryIdentifier
    unowned let dbStorage: DbStorage
    unowned let webDavController: WebDavController
    let queue: DispatchQueue

    var result: Single<Set<String>> {
        return self.loadDeletions()
                   .flatMap({ keys -> Single<WebDavDeletionResult> in
                       return self.webDavController.delete(keys: keys, queue: self.queue)
                   })
                   .flatMap({ result -> Single<Set<String>> in
                       if result.succeeded.isEmpty && result.missing.isEmpty {
                           return Single.just(result.failed)
                       }
                       return self.removeDeletions(keys: (result.succeeded.union(result.missing))).flatMap({ Single.just(result.failed) })
                   })
    }

    private func loadDeletions() -> Single<[String]> {
        return Single.create { subscriber in
            do {
                let keys: [String] = (try self.dbStorage.createCoordinator().perform(request: ReadWebDavDeletionsDbRequest(libraryId: self.libraryId))).map({ $0.key })
                subscriber(.success(keys))
            } catch let error {
                DDLogError("DeleteWebDavFilesSyncAction: could not read webdav deletions - \(error)")
                subscriber(.failure(error))
            }
            return Disposables.create()
        }
    }

    private func removeDeletions(keys: Set<String>) -> Single<()> {
        return Single.create { subscriber in
            do {
                try self.dbStorage.createCoordinator().perform(request: DeleteWebDavDeletionsDbRequest(keys: keys, libraryId: self.libraryId))
                subscriber(.success(()))
            } catch let error {
                DDLogError("DeleteWebDavFilesSyncAction: could not delete webdav deletions - \(error)")
                subscriber(.failure(error))
            }
            return Disposables.create()
        }
    }
}
