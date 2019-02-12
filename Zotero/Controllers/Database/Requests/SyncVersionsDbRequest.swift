//
//  SyncVersionsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 05/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

extension RLibrary: IdentifiableObject, VersionableObject {
    typealias IdType = Int
}

extension RCollection: IdentifiableObject, VersionableObject {
    typealias IdType = String
}

extension RItem: IdentifiableObject, VersionableObject {
    typealias IdType = String
}

typealias SyncableObject = IdentifiableObject&VersionableObject&Object

struct SyncVersionsDbRequest<Obj: SyncableObject>: DbResponseRequest {
    typealias Response = [Obj.IdType]

    let versions: [Obj.IdType: Int]
    let libraryId: Int?
    let isTrash: Bool
    let syncAll: Bool

    var needsWrite: Bool { return true }

    init(versions: [Obj.IdType: Int], parentLibraryId: Int?, isTrash: Bool, syncAll: Bool) {
        self.versions = versions
        self.libraryId = parentLibraryId
        self.isTrash = isTrash
        self.syncAll = syncAll
    }

    func process(in database: Realm) throws -> [Obj.IdType] {
        guard let primaryKeyName = Obj.primaryKey() else { throw DbError.primaryKeyUnavailable }
        let allKeys = Array(self.versions.keys)
        // Remove groups which are not in versions dictionary
        var toRemove = database.objects(Obj.self).filter("NOT \(primaryKeyName) IN %@", allKeys)
        if let identifier = self.libraryId {
            toRemove = toRemove.filter("library.identifier = %d", identifier)
        } else {
            toRemove = toRemove.filter("\(primaryKeyName) != %d", RLibrary.myLibraryId)
        }
        if self.isTrash {
            toRemove = toRemove.filter("trash = true")
        }
        database.delete(toRemove)

        if self.syncAll {
            return allKeys
        }

        // Go through remaining local groups and check which groups need an update
        var toUpdate: [Obj.IdType] = allKeys
        database.objects(Obj.self).forEach { object in
            if !object.needsSync,
               let version = self.versions[object.identifier], version == object.version {
                if let index = toUpdate.index(of: object.identifier) {
                    toUpdate.remove(at: index)
                }
            }
        }
        return toUpdate
    }
}
