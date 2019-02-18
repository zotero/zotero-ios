//
//  SyncVersionsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 05/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

extension RCollection: SyncableObject {
    func removeChildren(in database: Realm) {
        self.items.forEach { item in
            item.removeChildren(in: database)
        }
        database.delete(self.items)
        self.children.forEach { child in
            child.removeChildren(in: database)
        }
        database.delete(self.children)
    }
}

extension RItem: SyncableObject {
    func removeChildren(in database: Realm) {
        self.children.forEach { child in
            child.removeChildren(in: database)
        }
        database.delete(self.children)
    }
}

struct SyncVersionsDbRequest<Obj: Syncable>: DbResponseRequest {
    typealias Response = [String]

    let versions: [String: Int]
    let libraryId: Int
    let isTrash: Bool?
    let syncAll: Bool

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws -> [String] {
        let allKeys = Array(self.versions.keys)

        let libraryPredicate = NSPredicate(format: "library.identifier = %d", self.libraryId)
        let keyPredicate = NSPredicate(format: "NOT key IN %@", allKeys)
        var predicates = [libraryPredicate, keyPredicate]
        if let trash = self.isTrash {
            let trashPredicate = NSPredicate(format: "trash = %d", trash)
            predicates.append(trashPredicate)
        }
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

        let toRemove = database.objects(Obj.self).filter(predicate)
        for object in toRemove {
            object.removeChildren(in: database)
        }
        database.delete(toRemove)

        if self.syncAll { return allKeys }

        var toUpdate: [String] = allKeys
        database.objects(Obj.self).forEach { object in
            if !object.needsSync,
               let version = self.versions[object.key], version == object.version {
                if let index = toUpdate.index(of: object.key) {
                    toUpdate.remove(at: index)
                }
            }
        }
        return toUpdate
    }
}


struct SyncGroupVersionsDbRequest: DbResponseRequest {
    typealias Response = [Int]

    let versions: [Int: Int]
    let syncAll: Bool

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws -> [Int] {
        let allKeys = Array(self.versions.keys)

        let toRemove = database.objects(RLibrary.self)
                               .filter("identifier != %d AND (NOT identifier IN %@)", RLibrary.myLibraryId, allKeys)
        toRemove.forEach { library in
            library.collections.forEach { collection in
                collection.removeChildren(in: database)
            }
            database.delete(library.collections)
            library.items.forEach { item in
                item.removeChildren(in: database)
            }
            database.delete(library.items)
        }
        database.delete(toRemove)

        if self.syncAll { return allKeys }

        var toUpdate: [Int] = allKeys
        database.objects(RLibrary.self).forEach { library in
            if !library.needsSync && library.identifier != RLibrary.myLibraryId,
               let version = self.versions[library.identifier], version == library.version {
                if let index = toUpdate.index(of: library.identifier) {
                    toUpdate.remove(at: index)
                }
            }
        }
        return toUpdate
    }
}
