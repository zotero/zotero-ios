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
    typealias Result = (Int, [Int], [(Int, String)])

    let syncType: SyncController.SyncType
    let userId: Int

    unowned let apiClient: ApiClient
    unowned let dbStorage: DbStorage
    let queue: DispatchQueue
    let scheduler: SchedulerType

    var result: Single<(Int, [Int], [(Int, String)])> {
        let syncAll = syncType == .all
        let request = VersionsRequest<Int>(libraryId: .custom(.myLibrary), userId: self.userId, objectType: .group, version: nil)
        return self.apiClient.send(request: request, queue: self.queue)
                             .observeOn(self.scheduler)
                             .flatMap { (response: [Int: Int], headers) in
                                 let newVersion = headers.lastModifiedVersion
                                 let request =  SyncGroupVersionsDbRequest(versions: response, syncAll: syncAll)
                                 do {
                                     let (toUpdate, toRemove) = try self.dbStorage.createCoordinator().perform(request: request)
                                     return Single.just((newVersion, toUpdate, toRemove))
                                 } catch let error {
                                     return Single.error(error)
                                 }
                             }
    }
}
