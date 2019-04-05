//
//  SyncVersionsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 05/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

extension RCollection: Syncable {
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

extension RItem: Syncable {
    func removeChildren(in database: Realm) {
        self.children.forEach { child in
            child.removeChildren(in: database)
        }
        database.delete(self.children)
    }
}

extension RSearch: Syncable {
    func removeChildren(in database: Realm) {}
}

struct SyncVersionsDbRequest<Obj: SyncableObject>: DbResponseRequest {
    typealias Response = [String]

    let versions: [String: Int]
    let libraryId: LibraryIdentifier
    let isTrash: Bool?
    let syncAll: Bool

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws -> [String] {
        let allKeys = Array(self.versions.keys)

        if self.syncAll { return allKeys }

        var toUpdate: [String] = allKeys
        var objects = database.objects(Obj.self)
        if let trash = self.isTrash {
            objects = objects.filter("trash = %d", trash)
        }
        objects.forEach { object in
            if object.syncState != .synced {
                if !toUpdate.contains(object.key) {
                    toUpdate.append(object.key)
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
    typealias Response = [Int]

    let versions: [Int: Int]
    let syncAll: Bool

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws -> [Int] {
        let allKeys = Array(self.versions.keys)

        let toRemove = database.objects(RGroup.self).filter("NOT identifier IN %@", allKeys)
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
        return toUpdate
    }
}
