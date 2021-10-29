//
//  SubmitDeletionSyncAction.swift
//  Zotero
//
//  Created by Michal Rentka on 30/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxSwift

struct SubmitDeletionSyncAction: SyncAction {
    typealias Result = Int

    let keys: [String]
    let object: SyncObject
    let version: Int
    let libraryId: LibraryIdentifier
    let userId: Int

    unowned let apiClient: ApiClient
    unowned let dbStorage: DbStorage
    unowned let webDavController: WebDavController
    let queue: DispatchQueue
    let scheduler: SchedulerType

    var result: Single<Int> {
        let request = SubmitDeletionsRequest(libraryId: self.libraryId, userId: self.userId, objectType: self.object, keys: self.keys, version: self.version)
        return self.apiClient.send(request: request, queue: self.queue)
                             .observe(on: self.scheduler)
                             .flatMap({ _, response -> Single<Int> in
                                 return Single.just(response.allHeaderFields.lastModifiedVersion)
                             })
                             .flatMap({ version -> Single<Int> in
                                 return self.deleteFromDb(version: version).flatMap({ Single.just(version) })
                             })
    }

    private func deleteFromDb(version: Int) -> Single<()> {
        return Single.create { subscriber -> Disposable in
            do {
                let updateVersion = UpdateVersionsDbRequest(version: version, libraryId: self.libraryId, type: .object(self.object))
                var requests: [DbRequest] = [updateVersion]

                switch self.object {
                case .collection:
                    requests.insert(DeleteObjectsDbRequest<RCollection>(keys: self.keys, libraryId: self.libraryId), at: 0)
                case .item, .trash:
                    requests.insert(DeleteObjectsDbRequest<RItem>(keys: self.keys, libraryId: self.libraryId), at: 0)
                    requests.append(CreateWebDavDeletionsDbRequest(keys: self.keys, libraryId: self.libraryId))
                case .search:
                    requests.insert(DeleteObjectsDbRequest<RSearch>(keys: self.keys, libraryId: self.libraryId), at: 0)
                case .settings: break
                }

                try self.dbStorage.createCoordinator().perform(requests: requests)

                subscriber(.success(()))
            } catch let error {
                DDLogError("SubmitDeletionSyncAction: can't delete objects - \(error)")
                subscriber(.failure(error))
            }

            return Disposables.create()
        }
    }
}
