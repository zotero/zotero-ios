//
//  SyncGroupVersionsSyncAction.swift
//  Zotero
//
//  Created by Michal Rentka on 30/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RxSwift

struct SyncGroupVersionsSyncAction: SyncAction {
    typealias Result = ([Int], [(Int, String)])

    let userId: Int

    unowned let apiClient: ApiClient
    unowned let dbStorage: DbStorage
    let queue: DispatchQueue
    let scheduler: SchedulerType

    var result: Single<([Int], [(Int, String)])> {
        return self.apiClient.send(request: GroupVersionsRequest(userId: self.userId), queue: self.queue)
                             .observe(on: self.scheduler)
                             .flatMap { (response: [Int: Int], _) in
                                 do {
                                     let (toUpdate, toRemove) = try self.dbStorage.perform(request: SyncGroupVersionsDbRequest(versions: response), on: self.queue, invalidateRealm: true)
                                     return Single.just((toUpdate, toRemove))
                                 } catch let error {
                                     return Single.error(error)
                                 }
                             }
    }
}
