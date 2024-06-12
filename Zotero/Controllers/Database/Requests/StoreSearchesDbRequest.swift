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
        if let existing = database.objects(RSearch.self).uniqueObject(key: data.key, libraryId: libraryId) {
            search = existing
        } else {
            search = RSearch()
            database.add(search)
        }

        // No CR for searches, if it was changed or deleted locally, just restore it
        search.deleted = false
        search.deleteAllChanges(database: database)

        StoreSearchesDbRequest.update(search: search, response: data, libraryId: libraryId, database: database)
    }

    static func update(search: RSearch, response: SearchResponse, libraryId: LibraryIdentifier, database: Realm) {
        search.key = response.key
        search.name = response.data.name
        search.version = response.version
        search.syncState = .synced
        search.syncRetries = 0
        search.lastSyncDate = Date(timeIntervalSince1970: 0)
        search.changeType = .sync
        search.libraryId = libraryId
        search.trash = response.data.isTrash

        self.sync(conditions: response.data.conditions, search: search, database: database)
    }

    static func sync(conditions: [ConditionResponse], search: RSearch, database: Realm) {
        database.delete(search.conditions)

        for object in conditions.enumerated() {
            let condition = RCondition()
            condition.condition = object.element.condition
            condition.operator = object.element.operator
            condition.value = object.element.value
            condition.sortId = object.offset
            search.conditions.append(condition)
        }
    }
}
