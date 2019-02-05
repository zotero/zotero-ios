//
//  SyncGroupVersionsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 05/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct SyncGroupVersionsDbRequest: DbResponseRequest {
    typealias Response = [Int: Int]

    let versions: [Int: Int]

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws -> [Int : Int] {
        // Remove groups which are not in versions dictionary
        let toRemove = database.objects(RGroup.self).filter("NOT identifier IN %@", Array(self.versions.keys))
        database.delete(toRemove)

        // Go through remaining local groups and check which groups need an update
        var toUpdate: [Int: Int] = Dictionary(minimumCapacity: self.versions.capacity)
        for data in self.versions {
            toUpdate[data.key] = 0
        }

        let allGroups = database.objects(RGroup.self)
        for group in allGroups {
            guard let version = self.versions[group.identifier] else { continue }
            if version == group.version { // up to date, remove from result
                toUpdate.removeValue(forKey: group.identifier)
            } else { // needs update, set local version
                toUpdate[group.identifier] = group.version
            }
        }
        return toUpdate
    }
}
