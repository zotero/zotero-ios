//
//  StoreSearchesDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 25/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct StoreSearchesDbRequest: DbRequest {
    let response: [SearchResponse]

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        for data in self.response {
            try self.store(data: data, to: database)
        }
    }

    private func store(data: SearchResponse, to database: Realm) throws {
        guard let libraryId = data.library.libraryId else { throw DbError.primaryKeyUnavailable }
        let search: RSearch
        let predicate = Predicates.keyInLibrary(key: data.key, libraryId: libraryId)
        if let existing = database.objects(RSearch.self).filter(predicate).first {
            search = existing
        } else {
            search = RSearch()
            database.add(search)
        }

        search.key = data.key
        search.name = data.data.name
        search.version = data.version
        search.syncState = .synced
        search.deleted = false// no CR for searches, if it was deleted locally, just restore it

        try self.syncLibrary(identifier: libraryId, libraryName: data.library.name, search: search, database: database)
        self.syncConditions(data: data, search: search, database: database)
    }

    private func syncLibrary(identifier: LibraryIdentifier, libraryName: String,
                             search: RSearch, database: Realm) throws {
        let libraryData = try database.autocreatedLibraryObject(forPrimaryKey: identifier)
        if libraryData.0 {
            switch libraryData.1 {
            case .group(let object):
                object.name = libraryName
                object.syncState = .outdated

            case .custom: break // Custom library doesnt need sync or name update
            }
        }
        search.libraryObject = libraryData.1
    }

    private func syncConditions(data: SearchResponse, search: RSearch, database: Realm) {
        database.delete(search.conditions)

        for object in data.data.conditions.enumerated() {
            let condition = RCondition()
            condition.condition = object.element.condition
            condition.operator = object.element.operator
            condition.value = object.element.value
            condition.sortId = object.offset
            condition.search = search
            database.add(condition)
        }
    }
}
