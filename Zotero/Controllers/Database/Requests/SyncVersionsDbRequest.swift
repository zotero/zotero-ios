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
    let syncType: SyncController.SyncType
    let delayIntervals: [Double]

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> [String] {
        switch self.syncObject {
        case .collection:
            return self.check(versions: self.versions, for: database.objects(RCollection.self))

        case .search:
            return self.check(versions: self.versions, for: database.objects(RSearch.self))

        case .item:
            let objects = database.objects(RItem.self).filter(.isTrash(false))
            return self.check(versions: self.versions, for: objects)

        case .trash:
            let objects = database.objects(RItem.self).filter(.isTrash(true))
            return self.check(versions: self.versions, for: objects)

        case .settings:
            return []
        }
    }

    private func check<Obj: SyncableObject>(versions: [String: Int], for objects: Results<Obj>) -> [String] {
        let date = Date()
        var toUpdate = Array(self.versions.keys)

        for object in objects {
            if object.syncState == .synced {
                if let version = self.versions[object.key], version == object.version,
                   let index = toUpdate.firstIndex(of: object.key) {
                    toUpdate.remove(at: index)
                }
                continue
            }

            switch self.syncType {
            case .ignoreIndividualDelays, .full:
                guard !toUpdate.contains(object.key) else { continue }
                toUpdate.append(object.key)

            case .collectionsOnly, .normal, .keysOnly:
                // Check backoff schedule to see whether object can be synced again
                let delayIdx = min(object.syncRetries, (self.delayIntervals.count - 1))
                let delay = self.delayIntervals[delayIdx]
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
        let allKeys = Array(self.versions.keys)

        let toRemove = database.objects(RGroup.self).filter("NOT identifier IN %@", allKeys)
        let toRemoveIds = Array(toRemove.map({ ($0.identifier, $0.name) }))

        var toUpdate: [Int] = allKeys
        for library in database.objects(RGroup.self) {
            if library.syncState != .synced {
                if !toUpdate.contains(library.identifier) {
                    toUpdate.append(library.identifier)
                }
            } else {
                if let version = self.versions[library.identifier], version == library.version,
                   let index = toUpdate.firstIndex(of: library.identifier) {
                    toUpdate.remove(at: index)
                }
            }
        }

        return (toUpdate, toRemoveIds)
    }
}
