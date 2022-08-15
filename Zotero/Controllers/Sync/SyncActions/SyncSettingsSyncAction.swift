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
        let request = SettingsRequest(libraryId: self.libraryId, userId: self.userId, version: self.sinceVersion)
        return self.apiClient.send(request: request, queue: self.queue)
                             .mapData(httpMethod: request.httpMethod.rawValue)
                             .observe(on: self.scheduler)
                             .flatMap({ data, response -> Single<(SettingsResponse, ResponseHeaders)> in
                                 do {
                                     let jsonObject = try JSONSerialization.jsonObject(with: data, options: .allowFragments)
                                     let decoded = try SettingsResponse(response: jsonObject)
                                     return Single.just((decoded, response.allHeaderFields))
                                 } catch let error {
                                     return Single.error(error)
                                 }
                             })
                             .flatMap({ response, headers in
                                 let newVersion = headers.lastModifiedVersion

                                 if let current = self.currentVersion, newVersion != current {
                                     return Single.error(SyncError.NonFatal.versionMismatch(libraryId))
                                 }

                                 do {
                                     let request = StoreSettingsDbRequest(response: response, libraryId: self.libraryId)
                                     try self.dbStorage.perform(request: request, on: self.queue)
                                     let settingsChanged = newVersion != self.sinceVersion
                                     return Single.just((settingsChanged, newVersion))
                                 } catch let error {
                                     return Single.error(error)
                                 }
                             })
    }
}
