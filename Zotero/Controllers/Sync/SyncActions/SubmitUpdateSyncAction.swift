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
    let updateLibraryVersion: Bool

    unowned let apiClient: ApiClient
    unowned let dbStorage: DbStorage
    unowned let fileStorage: FileStorage
    unowned let schemaController: SchemaController
    unowned let dateParser: DateParser
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
                             .observe(on: self.scheduler)
                             .flatMap({ _, response -> Single<([(String, LibraryIdentifier)], Int)> in
                                 let newVersion = response.allHeaderFields.lastModifiedVersion
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
                                     var requests: [DbRequest] = [MarkSettingsAsSyncedDbRequest(settings: settings, version: newVersion)]
                                     if self.updateLibraryVersion {
                                         requests.append(UpdateVersionsDbRequest(version: newVersion, libraryId: self.libraryId, type: .object(self.object)))
                                     }
                                     try self.dbStorage.createCoordinator().perform(requests: requests)

                                     return Single.just((newVersion, nil))
                                 } catch let error {
                                     return Single.just((newVersion, error))
                                 }
                             })
    }

    private func submitOther() -> Single<(Int, Error?)> {
        let request = UpdatesRequest(libraryId: self.libraryId, userId: self.userId, objectType: self.object, params: self.parameters, version: self.sinceVersion)
        return self.apiClient.send(request: request, queue: self.queue)
                             .mapData(httpMethod: request.httpMethod.rawValue)
                             .observe(on: self.scheduler)
                             .flatMap({ data, response -> Single<(UpdatesResponse, Int)> in
                                 do {
                                     let newVersion = response.allHeaderFields.lastModifiedVersion
                                     let json = try JSONSerialization.jsonObject(with: data, options: .allowFragments)
                                     let keys = self.parameters.map({ $0["key"] as? String })
                                     return Single.just((try UpdatesResponse(json: json, keys: keys), newVersion))
                                 } catch let error {
                                     DDLogError("SubmitUpdateSyncAction: can't parse updates response - \(error)")
                                     return Single.error(error)
                                 }
                             })
                             .flatMap({ response, newVersion -> Single<(Int, Error?)> in
                                 return self.process(response: response, newVersion: newVersion)
                             })
    }

    private func process(response: UpdatesResponse, newVersion: Int) -> Single<(Int, Error?)> {
        return Single.create { subscriber in
            let requests = self.createRequests(response: response, version: newVersion, updateLibraryVersion: self.updateLibraryVersion)

            if !response.successfulJsonObjects.isEmpty {
                switch self.object {
                case .item, .trash:
                    // Cache JSONs locally for later use (in CR)
                    self.storeIndividualItemJsonObjects(from: Array(response.successfulJsonObjects.values), libraryId: self.libraryId)
                case .collection, .search, .settings: break
                }
            }

            if !requests.isEmpty {
                do {
                    try self.dbStorage.createCoordinator().perform(requests: requests)
                } catch let error {
                    DDLogError("SubmitUpdateSyncAction: can't store local changes - \(error)")
                    subscriber(.success((newVersion, error)))
                    return Disposables.create()
                }
            }

            let error = self.process(failedResponses: response.failed, in: self.libraryId)
            subscriber(.success((newVersion, error)))
            return Disposables.create()
        }
    }

    private func process(failedResponses: [FailedUpdateResponse], in libraryId: LibraryIdentifier) -> Error? {
        guard !failedResponses.isEmpty else { return nil }

        var splitKeys: Set<String> = []

        for response in failedResponses {
            switch response.code {
            case 412:
                DDLogError("SubmitUpdateSyncAction: failed \(response.key ?? "unknown key") - \(response.message). Library \(libraryId)")
                return PreconditionErrorType.objectConflict

            case 400 where response.message == "Annotation position is too long":
                if let key = response.key {
                    splitKeys.insert(key)
                }

            default: continue
            }
        }

        if !splitKeys.isEmpty {
            DDLogWarn("SubmitUpdateSyncAction: annotations too long: \(splitKeys) in \(libraryId)")

            do {
                try self.dbStorage.createCoordinator().perform(request: SplitAnnotationsDbRequest(keys: splitKeys, libraryId: libraryId))
                return SyncActionError.annotationNeededSplitting(libraryId)
            } catch let error {
                DDLogError("SubmitUpdateSyncAction: could not split annotations - \(error)")
            }
        }

        DDLogError("SubmitUpdateSyncAction: failures - \(failedResponses)")

        let errorMessages = failedResponses.map({ $0.message }).joined(separator: "\n")
        return SyncActionError.submitUpdateFailures(errorMessages)
    }

    private func process(response: UpdatesResponse) -> (unchangedKeys: [String], parsingFailedKeys: [String], changedCollections: [CollectionResponse], changedItems: [ItemResponse], changedSearches: [SearchResponse]) {
        var unchangedKeys: [String] = Array(response.unchanged.values)
        var changedCollections: [CollectionResponse] = []
        var changedItems: [ItemResponse] = []
        var changedSearches: [SearchResponse] = []
        var parsingFailedKeys: [String] = []

        for (idx, json) in response.successfulJsonObjects {
            guard let key = response.successful[idx] else { continue }

            do {
                switch self.object {
                case .collection:
                    let response = try CollectionResponse(response: json)
                    changedCollections.append(response)
                case .item, .trash:
                    let response = try ItemResponse(response: json, schemaController: self.schemaController)
                    changedItems.append(response)
                case .search:
                    let response = try SearchResponse(response: json)
                    changedSearches.append(response)
                case .settings: break
                }
            } catch let error {
                DDLogError("SubmitUpdateSyncAction: could not parse json for object \(self.object) - \(error)")
                // Since changes were submitted to backend and only the response can't be parsed, we'll mark it as submitted so that we don't try to resubmit the same changes.
                unchangedKeys.append(key)
                // We'll also mark this object as outdated so that it's updated from backend on next sync.
                parsingFailedKeys.append(key)
            }
        }

        return (unchangedKeys, parsingFailedKeys, changedCollections, changedItems, changedSearches)
    }

    private func createRequests(response: UpdatesResponse, version: Int, updateLibraryVersion: Bool) -> [DbRequest] {
        let (unchangedKeys, parsingFailedKeys, changedCollections, changedItems, changedSearches) = self.process(response: response)

        var requests: [DbRequest] = []

        if !unchangedKeys.isEmpty {
            // Mark unchanged objects as submitted.
            switch self.object {
            case .collection:
                requests.append(MarkObjectsAsSyncedDbRequest<RCollection>(libraryId: self.libraryId, keys: unchangedKeys, version: version))
            case .item, .trash:
                requests.append(MarkObjectsAsSyncedDbRequest<RItem>(libraryId: self.libraryId, keys: unchangedKeys, version: version))
            case .search:
                requests.append(MarkObjectsAsSyncedDbRequest<RSearch>(libraryId: self.libraryId, keys: unchangedKeys, version: version))
            case .settings: break
            }
        }

        if !parsingFailedKeys.isEmpty {
            // Marked objects which failed to parse response as outdated so that they are updated on next sync.
            switch self.object {
            case .collection:
                requests.append(MarkForResyncDbAction<RCollection>(libraryId: self.libraryId, keys: unchangedKeys))
            case .item, .trash:
                requests.append(MarkForResyncDbAction<RItem>(libraryId: self.libraryId, keys: unchangedKeys))
            case .search:
                requests.append(MarkForResyncDbAction<RSearch>(libraryId: self.libraryId, keys: unchangedKeys))
            case .settings: break
            }
        }

        if !changedCollections.isEmpty {
            // Update collections locally based on response from backend and mark as submitted.
            for response in changedCollections {
                requests.append(MarkCollectionAsSyncedAndUpdateDbRequest(libraryId: self.libraryId, response: response, version: version))
            }
        }

        if !changedItems.isEmpty {
            // Update items locally based on response from backend and mark as submitted.
            for response in changedItems {
                requests.append(MarkItemAsSyncedAndUpdateDbRequest(libraryId: self.libraryId, response: response, version: version, schemaController: self.schemaController, dateParser: self.dateParser))
            }
        }

        if !changedSearches.isEmpty {
            // Update searches locally based on response from backend and mark as submitted.
            for response in changedSearches {
                requests.append(MarkSearchAsSyncedAndUpdateDbRequest(libraryId: self.libraryId, response: response, version: version))
            }
        }

        if updateLibraryVersion {
            requests.append(UpdateVersionsDbRequest(version: version, libraryId: self.libraryId, type: .object(self.object)))
        }

        return requests
    }

    private func storeIndividualItemJsonObjects(from jsonObjects: [[String: Any]], libraryId: LibraryIdentifier) {
        for object in jsonObjects {
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
