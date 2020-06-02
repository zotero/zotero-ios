//
//  SyncSettingsSyncAction.swift
//  Zotero
//
//  Created by Michal Rentka on 30/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RxSwift

struct SyncSettingsSyncAction: SyncAction {
    typealias Result = (Bool, Int) // hasTags, newVersion

    let currentVersion: Int?
    let sinceVersion: Int
    let libraryId: LibraryIdentifier
    let userId: Int

    unowned let apiClient: ApiClient
    unowned let dbStorage: DbStorage
    let queue: DispatchQueue
    let scheduler: SchedulerType

    var result: Single<(Bool, Int)> {
        return self.apiClient.send(request: SettingsRequest(libraryId: self.libraryId, userId: self.userId, version: self.sinceVersion),
                                   queue: self.queue)
                            .observeOn(self.scheduler)
                            .flatMap({ (response: SettingsResponse, headers) in

                                let newVersion = headers.lastModifiedVersion

                                if let current = self.currentVersion, newVersion != current {
                                    return Single.error(SyncError.versionMismatch)
                                }

                                do {
                                    let request = StoreSettingsDbRequest(response: response, libraryId: self.libraryId)
                                    try self.dbStorage.createCoordinator().perform(request: request)
                                    let settingsChanged = newVersion != self.sinceVersion
                                    return Single.just((settingsChanged, newVersion))
                                } catch let error {
                                    return Single.error(error)
                                }
                            })
    }
}
