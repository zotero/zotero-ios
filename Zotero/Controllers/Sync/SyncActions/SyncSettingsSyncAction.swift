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
    let sinceVersion: Int?
    let libraryId: LibraryIdentifier
    let userId: Int

    unowned let apiClient: ApiClient
    unowned let dbStorage: DbStorage

    var result: Single<(Bool, Int)> {
        return self.apiClient.send(request: SettingsRequest(libraryId: self.libraryId, userId: self.userId, version: self.sinceVersion))
                            .flatMap({ (response: SettingsResponse, headers) in

                                let newVersion = self.lastVersion(from: headers)

                                if let current = self.currentVersion, newVersion != current {
                                    return Single.error(SyncError.versionMismatch)
                                }

                                do {
                                    let request = StoreSettingsDbRequest(response: response, libraryId: self.libraryId)
                                    try self.dbStorage.createCoordinator().perform(request: request)
                                    let count = response.tagColors?.value.count ?? 0
                                    return Single.just(((count > 0), newVersion))
                                } catch let error {
                                    return Single.error(error)
                                }
                            })
    }

    private func lastVersion(from headers: ResponseHeaders) -> Int {
        // Workaround for broken headers (stored in case-sensitive dictionary) on iOS
        let lowercase = headers["last-modified-version"] as? String
        let uppercase = headers["Last-Modified-Version"] as? String
        return (lowercase ?? uppercase).flatMap(Int.init) ?? 0
    }
}
