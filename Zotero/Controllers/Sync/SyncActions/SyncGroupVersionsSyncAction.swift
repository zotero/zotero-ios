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

    let libraryId: LibraryIdentifier
    let syncType: SyncController.SyncType
    let userId: Int

    unowned let apiClient: ApiClient
    unowned let dbStorage: DbStorage
    let queue: DispatchQueue

    var result: Single<(Int, [Int], [(Int, String)])> {
        let syncAll = syncType == .all
        let request = VersionsRequest<Int>(libraryId: libraryId, userId: userId, objectType: .group, version: nil)
        return self.apiClient.send(request: request, queue: self.queue)
                             .flatMap { (response: [Int: Int], headers) in
                                 let newVersion = self.lastVersion(from: headers)
                                 let request =  SyncGroupVersionsDbRequest(versions: response, syncAll: syncAll)
                                 do {
                                     let (toUpdate, toRemove) = try self.dbStorage.createCoordinator().perform(request: request)
                                     return Single.just((newVersion, toUpdate, toRemove))
                                 } catch let error {
                                     return Single.error(error)
                                 }
                             }
    }

    private func lastVersion(from headers: ResponseHeaders) -> Int {
        // Workaround for broken headers (stored in case-sensitive dictionary) on iOS
        let lowercase = headers["last-modified-version"] as? String
        let uppercase = headers["Last-Modified-Version"] as? String
        return (lowercase ?? uppercase).flatMap(Int.init) ?? 0
    }
}
