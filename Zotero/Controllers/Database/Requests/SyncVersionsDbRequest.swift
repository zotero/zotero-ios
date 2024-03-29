//
//  SyncVersionsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 05/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct SyncVersionsDbRequest: DbResponseRequest {
    typealias Response = [String]

    let versions: [String: Int]
    let libraryId: LibraryIdentifier
    let syncObject: SyncObject
    let syncType: SyncController.Kind
    let delayIntervals: [Double]

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> [String] {
        switch syncObject {
        case .collection:
            return check(versions: versions, for: database.objects(RCollection.self).filter(.library(with: libraryId)))

        case .search:
            return check(versions: versions, for: database.objects(RSearch.self).filter(.library(with: libraryId)))

        case .item:
            let objects = database.objects(RItem.self).filter(.library(with: libraryId)).filter(.isTrash(false))
            return check(versions: versions, for: objects)

        case .trash:
            let objects = database.objects(RItem.self).filter(.library(with: libraryId)).filter(.isTrash(true))
            return check(versions: versions, for: objects)

        case .settings:
            return []
        }
    }

    private func check<Obj: SyncableObject>(versions: [String: Int], for objects: Results<Obj>) -> [String] {
        let date = Date()
        var toUpdate = Array(versions.keys)

        for object in objects {
            if object.syncState == .synced {
                if let version = versions[object.key], version == object.version,
                   let index = toUpdate.firstIndex(of: object.key) {
                    toUpdate.remove(at: index)
                }
                continue
            }

            switch syncType {
            case .ignoreIndividualDelays, .full:
                guard !toUpdate.contains(object.key) else { continue }
                toUpdate.append(object.key)

            case .collectionsOnly, .normal, .keysOnly, .prioritizeDownloads:
                // Check backoff schedule to see whether object can be synced again
                let delayIdx = min(object.syncRetries, (delayIntervals.count - 1))
                let delay = delayIntervals[delayIdx]
                if date.timeIntervalSince(object.lastSyncDate) >= delay {
                    // Object can be synced, if it's not already in array, add it.
                    guard !toUpdate.contains(object.key) else { continue }
                    toUpdate.append(object.key)
                } else {
                    // Object can't be synced yet, remove from array if it's there.
                    if let index = toUpdate.firstIndex(of: object.key) {
                        toUpdate.remove(at: index)
                    }
                }
            }
        }

        return toUpdate
    }
}

struct SyncGroupVersionsDbRequest: DbResponseRequest {
    typealias Response = ([Int], [(Int, String)])

    let versions: [Int: Int]

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> ([Int], [(Int, String)]) {
        let allKeys = Array(versions.keys)

        let toRemove = database.objects(RGroup.self).filter("NOT identifier IN %@", allKeys)
        let toRemoveIds = Array(toRemove.map({ ($0.identifier, $0.name) }))

        var toUpdate: [Int] = allKeys
        for library in database.objects(RGroup.self) {
            if library.syncState != .synced {
                if !toUpdate.contains(library.identifier) {
                    toUpdate.append(library.identifier)
                }
            } else {
                if let version = versions[library.identifier], version == library.version,
                   let index = toUpdate.firstIndex(of: library.identifier) {
                    toUpdate.remove(at: index)
                }
            }
        }

        return (toUpdate, toRemoveIds)
    }
}
