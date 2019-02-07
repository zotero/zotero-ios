//
//  SyncVersionsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 05/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

extension RGroup: IdentifiableObject, VersionableObject {
    typealias IdType = Int
}

extension RCollection: IdentifiableObject, VersionableObject {
    typealias IdType = String
}

extension RItem: IdentifiableObject, VersionableObject {
    typealias IdType = String
}

typealias SyncVersionObject = IdentifiableObject&VersionableObject&Object

struct SyncVersionsDbRequest<Obj: SyncVersionObject>: DbResponseRequest {
    typealias Response = [Obj.IdType]

    let versions: [Obj.IdType: Int]

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws -> [Obj.IdType] {
        guard let primaryKeyName = Obj.primaryKey() else { throw DbError.primaryKeyUnavailable }
        // Remove groups which are not in versions dictionary
        let toRemove = database.objects(Obj.self).filter("NOT \(primaryKeyName) IN %@", Array(self.versions.keys))
        database.delete(toRemove)

        // Go through remaining local groups and check which groups need an update
        var toUpdate: [Obj.IdType] = []
        database.objects(Obj.self).forEach { object in
            if let version = self.versions[object.identifier], version != object.version {
                toUpdate.append(object.identifier)
            }
        }
        return toUpdate
    }
}
