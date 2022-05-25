//
//  FetchAndStoreGroupSyncAction.swift
//  Zotero
//
//  Created by Michal Rentka on 02/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxSwift

struct FetchAndStoreGroupSyncAction: SyncAction {
    typealias Result = ()

    let identifier: Int
    let userId: Int

    unowned let apiClient: ApiClient
    unowned let dbStorage: DbStorage
    let queue: DispatchQueue
    let scheduler: SchedulerType

    var result: Single<()> {
        return self.apiClient.send(request: GroupRequest(identifier: self.identifier), queue: self.queue)
                             .observe(on: self.scheduler)
                             .flatMap({ (response: GroupResponse, headers) -> Single<()> in
                                 do {
                                     try self.dbStorage.perform(request: StoreGroupDbRequest(response: response, userId: self.userId), on: self.queue)
                                     return Single.just(())
                                 } catch let error {
                                     return Single.error(error)
                                 }
                             })
    }
}
