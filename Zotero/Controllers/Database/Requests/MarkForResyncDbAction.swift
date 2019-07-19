//
//  MarkForResyncDbAction.swift
//  Zotero
//
//  Created by Michal Rentka on 08/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct MarkForResyncDbAction<Obj: SyncableObject>: DbRequest {
    let libraryId: LibraryIdentifier
    let keys: [String]

    var needsWrite: Bool { return true }

    init(libraryId: LibraryIdentifier, keys: [Any]) throws {
        guard let typedKeys = keys as? [String] else { throw DbError.primaryKeyWrongType }
        self.libraryId = libraryId
        self.keys = typedKeys
    }

    func process(in database: Realm) throws {
        let syncDate = Date()
        var toCreate: [String] = self.keys
        let objects = database.objects(Obj.self).filter(Predicates.keys(self.keys, in: self.libraryId))
        objects.forEach { object in
            if object.syncState == .synced {
                object.syncState = .outdated
            }
            object.syncRetries += 1
            object.lastSyncDate = syncDate
            if let index = toCreate.firstIndex(of: object.key) {
                toCreate.remove(at: index)
            }
        }

        let (isNew, libraryObject) = try database.autocreatedLibraryObject(forPrimaryKey: self.libraryId)
        if isNew {
            switch libraryObject {
            case .group(let group):
                group.syncState = .dirty
            case .custom: break
            }
        }

        toCreate.forEach { key in
            let object = Obj()
            object.key = key
            object.syncState = .dirty
            object.syncRetries = 1
            object.lastSyncDate = syncDate
            object.libraryObject = libraryObject
            database.add(object)
        }
    }
}

struct MarkGroupForResyncDbAction: DbRequest {
    let identifiers: [Int]

    var needsWrite: Bool { return true }

    init(identifiers: [Any]) throws {
        guard let typedIds = identifiers as? [Int] else { throw DbError.primaryKeyWrongType }
        self.identifiers = typedIds
    }

    func process(in database: Realm) throws {
        var toCreate: [Int] = self.identifiers
        let libraries = database.objects(RGroup.self).filter("identifier IN %@", self.identifiers)
        libraries.forEach { library in
            if let index = toCreate.firstIndex(of: library.identifier) {
                toCreate.remove(at: index)
            }
            if library.syncState == .synced {
                library.syncState = .outdated
            }
        }

        toCreate.forEach { identifier in
            let library = RGroup()
            library.identifier = identifier
            library.syncState = .dirty
            database.add(library)
        }
    }
}
