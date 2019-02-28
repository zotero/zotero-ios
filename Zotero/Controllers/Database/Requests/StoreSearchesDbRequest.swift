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
        let search: RSearch
        if let existing = database.objects(RSearch.self)
                                  .filter("key = %@ AND library.identifier = %d", data.key,
                                                                                  data.library.libraryId).first {
            search = existing
        } else {
            search = RSearch()
            database.add(search)
        }

        search.key = data.key
        search.name = data.data.name
        search.version = data.version
        search.needsSync = false

        try self.syncLibrary(data: data, search: search, database: database)
        self.syncConditions(data: data, search: search, database: database)
    }

    private func syncLibrary(data: SearchResponse, search: RSearch, database: Realm) throws {
        let libraryData = try database.autocreatedObject(ofType: RLibrary.self, forPrimaryKey: data.library.libraryId)
        if libraryData.0 {
            libraryData.1.name = data.library.name
            libraryData.1.needsSync = true
        }
        search.library = libraryData.1
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
