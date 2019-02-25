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
        var existingIndices: Set<Int> = []

        search.conditions.forEach { condition in
            let responseIndex = data.data.conditions.index(where: { response -> Bool in
                return response.condition == condition.condition &&
                       response.operator == condition.operator &&
                       response.value == condition.value
            })

            if let index = responseIndex {
                existingIndices.insert(index)
            } else {
                if let index = condition.searches.index(of: search) {
                    condition.searches.remove(at: index)
                }
            }
        }

        for object in data.data.conditions.enumerated() {
            guard !existingIndices.contains(object.offset) else { continue }

            let condition: RCondition
            if let existing = database.objects(RCondition.self).filter("condition = %@ AND operator = %@ AND" +
                                                                       " value = %@", object.element.condition,
                                                                                      object.element.operator,
                                                                                      object.element.value).first {
                condition = existing
            } else {
                condition = RCondition()
                condition.condition = object.element.condition
                condition.operator = object.element.operator
                condition.value = object.element.value
                database.add(condition)
            }

            condition.searches.append(search)
        }
    }
}
