//
//  SyncVersionsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 05/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct SyncVersionsDbRequest<Obj: SyncableObject>: DbResponseRequest {
    typealias Response = [String]

    let versions: [String: Int]
    let libraryId: LibraryIdentifier
    let isTrash: Bool?
    let syncType: SyncController.SyncType
    let delayIntervals: [Double]

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> [String] {
        let allKeys = Array(self.versions.keys)

        if self.syncType == .all && !allKeys.isEmpty { return allKeys }

        let date = Date()
        var toUpdate: [String] = allKeys
        var objects = database.objects(Obj.self)
        if let trash = self.isTrash {
            objects = objects.filter("trash = %d", trash)
        }

        for object in objects {
            if object.syncState != .synced {
                guard !toUpdate.contains(object.key) else { continue }

                if self.syncType == .ignoreIndividualDelays {
                    toUpdate.append(object.key)
                } else {
                    let delayIdx = min(object.syncRetries, (self.delayIntervals.count - 1))
                    let delay = self.delayIntervals[delayIdx]
                    if date.timeIntervalSince(object.lastSyncDate) >= delay {
                        toUpdate.append(object.key)
                    }
                }
            } else {
                if let version = self.versions[object.key], version == object.version,
                   let index = toUpdate.firstIndex(of: object.key) {
                    toUpdate.remove(at: index)
                }
            }
        }

        return toUpdate
    }
}


struct SyncGroupVersionsDbRequest: DbResponseRequest {
    typealias Response = ([Int], [(Int, String)])

    let versions: [Int: Int]
    let syncAll: Bool

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> ([Int], [(Int, String)]) {
        let allKeys = Array(self.versions.keys)

        let toRemove = database.objects(RGroup.self).filter("NOT identifier IN %@", allKeys)
        let toRemoveIds = Array(toRemove.map({ ($0.identifier, $0.name) }))

        if self.syncAll { return (allKeys, toRemoveIds) }

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
