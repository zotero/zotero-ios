//
//  SubmitUpdateSyncAction.swift
//  Zotero
//
//  Created by Michal Rentka on 30/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import Alamofire
import CocoaLumberjack
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
        let request = UpdatesRequest(libraryId: self.libraryId, userId: self.userId, objectType: self.object,
                                     params: self.parameters, version: self.sinceVersion)
        return self.apiClient.send(request: request, queue: self.queue)
                             .observeOn(self.scheduler)
                             .flatMap({ response, headers -> Single<UpdatesResponse> in
                                 do {
                                     let newVersion = headers.lastModifiedVersion
                                     let json = try JSONSerialization.jsonObject(with: response, options: .allowFragments)
                                     return Single.just((try UpdatesResponse(json: json, newVersion: newVersion)))
                                 } catch let error {
                                     return Single.error(error)
                                 }
                             })
                             .flatMap({ response -> Single<(Int, Error?)> in
                                let syncedKeys = self.keys(from: (response.successful + response.unchanged), parameters: self.parameters)

                                 do {
                                     let coordinator = try self.dbStorage.createCoordinator()
                                     switch self.object {
                                     case .collection:
                                         let request = MarkObjectsAsSyncedDbRequest<RCollection>(libraryId: self.libraryId,
                                                                                                 keys: syncedKeys,
                                                                                                 version: response.newVersion)
                                         try coordinator.perform(request: request)
                                     case .item, .trash:
                                        // Cache JSONs locally for later use (in CR)
                                        self.storeIndividualItemJsonObjects(from: response.successfulJsonObjects,
                                                                            keys: nil,
                                                                            libraryId: self.libraryId)

                                        let request = MarkObjectsAsSyncedDbRequest<RItem>(libraryId: self.libraryId,
                                                                                          keys: syncedKeys,
                                                                                          version: response.newVersion)
                                        try coordinator.perform(request: request)
                                     case .search:
                                        let request = MarkObjectsAsSyncedDbRequest<RSearch>(libraryId: self.libraryId,
                                                                                            keys: syncedKeys,
                                                                                            version: response.newVersion)
                                        try coordinator.perform(request: request)
                                     case .group, .tag:
                                         fatalError("SyncActionHandler: unsupported update request")
                                     }

                                     let updateVersion = UpdateVersionsDbRequest(version: response.newVersion,
                                                                                 libraryId: self.libraryId,
                                                                                 type: .object(self.object))
                                     try coordinator.perform(request: updateVersion)
                                 } catch let error {
                                     return Single.just((response.newVersion, error))
                                 }

                                 if response.failed.first(where: { $0.code == 412 }) != nil {
                                     return Single.just((response.newVersion, PreconditionErrorType.objectConflict))
                                 }

                                 if response.failed.first(where: { $0.code == 409 }) != nil {
                                     let error = AFError.responseValidationFailed(reason: .unacceptableStatusCode(code: 409))
                                     return Single.just((response.newVersion, error))
                                 }

                                 return Single.just((response.newVersion, nil))
                             })
    }

    private func keys(from indices: [String], parameters: [[String: Any]]) -> [String] {
        return indices.compactMap({ Int($0) }).map({ parameters[$0] }).compactMap({ $0["key"] as? String })
    }

    private func storeIndividualItemJsonObjects(from jsonObject: Any, keys: [String]?, libraryId: LibraryIdentifier) {
        guard let array = jsonObject as? [[String: Any]] else { return }

        for object in array {
            guard let key = object["key"] as? String, (keys?.contains(key) ?? true) else { continue }

            do {
                let data = try JSONSerialization.data(withJSONObject: object, options: [])
                let file = Files.objectFile(for: .item, libraryId: libraryId, key: key, ext: "json")
                try self.fileStorage.write(data, to: file, options: .atomicWrite)
            } catch let error {
                DDLogError("FetchAndStoreObjectsSyncAction: can't encode/write item - \(error)\n\(object)")
            }
        }
    }
}
