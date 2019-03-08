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
    let libraryId: Int
    let keys: [String]

    var needsWrite: Bool { return true }

    init(libraryId: Int, keys: [Any]) throws {
        guard let typedKeys = keys as? [String] else { throw DbError.primaryKeyWrongType }
        self.libraryId = libraryId
        self.keys = typedKeys
    }

    func process(in database: Realm) throws {
        var toCreate: [String] = self.keys
        let objects = database.objects(Obj.self)
                              .filter("library.identifier = %d AND key IN %@", self.libraryId, self.keys)
        objects.forEach { object in
            object.needsSync = true
            if let index = toCreate.index(of: object.key) {
                toCreate.remove(at: index)
            }
        }

        let libraryData = try database.autocreatedObject(ofType: RLibrary.self, forPrimaryKey: self.libraryId)
        let library = libraryData.1
        if libraryData.0 {
            library.needsSync = true
        }

        toCreate.forEach { key in
            let object = Obj()
            object.key = key
            object.needsSync = true
            object.library = library
            database.add(object)
        }
    }
}

struct MarkLibraryForResyncDbAction: DbRequest {
    let identifiers: [Int]

    var needsWrite: Bool { return true }

    init(identifiers: [Any]) throws {
        guard let typedIds = identifiers as? [Int] else { throw DbError.primaryKeyWrongType }
        self.identifiers = typedIds
    }

    func process(in database: Realm) throws {
        var toCreate: [Int] = self.identifiers
        let libraries = database.objects(RLibrary.self).filter("identifier IN %@", self.identifiers)
        libraries.forEach { library in
            if let index = toCreate.index(of: library.identifier) {
                toCreate.remove(at: index)
            }
            library.needsSync = true
        }

        toCreate.forEach { identifier in
            let library = RLibrary()
            library.identifier = identifier
            library.needsSync = true
            database.add(library)
        }
    }
}
