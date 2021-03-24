//
//  SubmitUpdateSyncAction.swift
//  Zotero
//
//  Created by Michal Rentka on 30/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import Alamofire
import CocoaLumberjackSwift
import RxSwift

struct SubmitUpdateSyncAction: SyncAction {
    typealias Result = (Int, Error?)

    let parameters: [[String : Any]]
    let sinceVersion: Int?
    let object: SyncObject
    let libraryId: LibraryIdentifier
    let userId: Int

    unowned let apiClient: ApiClient
    unowned let dbStorage: DbStorage
    unowned let fileStorage: FileStorage
    let queue: DispatchQueue
    let scheduler: SchedulerType

    var result: Single<(Int, Error?)> {
        switch self.object {
        case .settings:
            return self.submitSettings()
        case .collection, .item, .search, .trash:
            return self.submitOther()
        }
    }

    private func submitSettings() -> Single<(Int, Error?)> {
        let request = UpdatesRequest(libraryId: self.libraryId, userId: self.userId, objectType: self.object, params: self.parameters, version: self.sinceVersion)
        return self.apiClient.send(request: request, queue: self.queue)
                             .observeOn(self.scheduler)
                             .flatMap({ _, headers -> Single<([(String, LibraryIdentifier)], Int)> in
                                 let newVersion = headers.lastModifiedVersion
                                 var settings: [(String, LibraryIdentifier)] = []
                                 for params in self.parameters {
                                     guard let key = params.keys.first,
                                           let setting = try? PageIndexResponse.parse(key: key) else { continue }
                                    settings.append(setting)
                                 }
                                 return Single.just((settings, newVersion))
                             })
                             .flatMap({ settings, newVersion -> Single<(Int, Error?)> in

                                 do {
                                     let request = MarkSettingsAsSyncedDbRequest(settings: settings, version: newVersion)
                                     let updateVersion = UpdateVersionsDbRequest(version: newVersion, libraryId: self.libraryId, type: .object(self.object))
                                     try self.dbStorage.createCoordinator().perform(requests: [request, updateVersion])

                                     return Single.just((newVersion, nil))
                                 } catch let error {
                                     return Single.just((newVersion, error))
                                 }
                             })
    }

    private func submitOther() -> Single<(Int, Error?)> {
        let request = UpdatesRequest(libraryId: self.libraryId, userId: self.userId, objectType: self.object, params: self.parameters, version: self.sinceVersion)
        return self.apiClient.send(request: request, queue: self.queue)
                             .observeOn(self.scheduler)
                             .flatMap({ response, headers -> Single<(UpdatesResponse, Int)> in
                                 do {
                                     let newVersion = headers.lastModifiedVersion
                                     let json = try JSONSerialization.jsonObject(with: response, options: .allowFragments)
                                     return Single.just((try UpdatesResponse(json: json), newVersion))
                                 } catch let error {
                                     return Single.error(error)
                                 }
                             })
                             .flatMap({ response, newVersion -> Single<(Int, Error?)> in
                                let syncedKeys = self.keys(from: (response.successful + response.unchanged), parameters: self.parameters)

                                 do {
                                     var requests: [DbRequest] = [UpdateVersionsDbRequest(version: newVersion, libraryId: self.libraryId, type: .object(self.object))]
                                     if !syncedKeys.isEmpty {
                                         switch self.object {
                                         case .collection:
                                             requests.insert(MarkObjectsAsSyncedDbRequest<RCollection>(libraryId: self.libraryId, keys: syncedKeys, version: newVersion), at: 0)
                                         case .item, .trash:
                                            // Cache JSONs locally for later use (in CR)
                                            self.storeIndividualItemJsonObjects(from: response.successfulJsonObjects, libraryId: self.libraryId)
                                            requests.insert(MarkObjectsAsSyncedDbRequest<RItem>(libraryId: self.libraryId, keys: syncedKeys, version: newVersion), at: 0)
                                         case .search:
                                            requests.insert(MarkObjectsAsSyncedDbRequest<RSearch>(libraryId: self.libraryId, keys: syncedKeys, version: newVersion), at: 0)
                                         case .settings: break
                                         }
                                     }
                                     try self.dbStorage.createCoordinator().perform(requests: requests)
                                 } catch let error {
                                     return Single.just((newVersion, error))
                                 }

                                 if response.failed.first(where: { $0.code == 412 }) != nil {
                                     return Single.just((newVersion, PreconditionErrorType.objectConflict))
                                 }

                                 if response.failed.first(where: { $0.code == 409 }) != nil {
                                     let error = AFError.responseValidationFailed(reason: .unacceptableStatusCode(code: 409))
                                     return Single.just((newVersion, error))
                                 }

                                 if !response.failed.isEmpty {
                                     DDLogError("SubmitUpdateSyncAction: unknown failures - \(response.failed)")
                                     return Single.just((newVersion, SyncActionError.submitUpdateUnknownFailures))
                                 }

                                 return Single.just((newVersion, nil))
                             })
    }

    private func keys(from indices: [String], parameters: [[String: Any]]) -> [String] {
        return indices.compactMap({ Int($0) }).map({ parameters[$0] }).compactMap({ $0["key"] as? String })
    }

    private func storeIndividualItemJsonObjects(from jsonObject: Any, libraryId: LibraryIdentifier) {
        guard let array = jsonObject as? [[String: Any]] else { return }

        for object in array {
            guard let key = object["key"] as? String else { continue }

            do {
                let data = try JSONSerialization.data(withJSONObject: object, options: [])
                let file = Files.jsonCacheFile(for: .item, libraryId: libraryId, key: key)
                try self.fileStorage.write(data, to: file, options: .atomicWrite)
            } catch let error {
                DDLogError("SubmitUpdateSyncAction: can't encode/write item - \(error)\n\(object)")
            }
        }
    }
}
