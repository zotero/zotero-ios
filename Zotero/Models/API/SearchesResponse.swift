//
//  SearchesResponse.swift
//  Zotero
//
//  Created by Michal Rentka on 25/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct SearchResponse {
    struct Data {
        let name: String
        let conditions: [ConditionResponse]
    }

    let key: String
    let library: LibraryResponse
    let links: LinksResponse?
    let data: SearchResponse.Data
    let version: Int

    init(response: [String: Any]) throws {
        let key: String = try response.apiGet(key: "key")
        let library: [String: Any] = try response.apiGet(key: "library")
        let data: [String: Any] = try response.apiGet(key: "data")

        self.key = key
        self.library = try LibraryResponse(response: library)
        self.links = try (response["links"] as? [String: Any]).flatMap { try LinksResponse(response: $0) }
        self.version = try response.apiGet(key: "version")
        self.data = try Data(response: data, key: key)
    }
}

extension SearchResponse.Data {
    init(response: [String: Any], key: String) throws {
        // Check for unknown fields
        if let unknownKey = response.keys.first(where: { !SearchFieldKeys.knownDataKeys.contains($0) }) {
            throw Parsing.Error.unknownField(key: key, field: unknownKey)
        }

        let conditions: [[String: Any]] = try response.apiGet(key: "conditions")

        self.name = try response.apiGet(key: "name")
        self.conditions = try conditions.map({ try ConditionResponse(response: $0) })
    }
}

struct ConditionResponse {
    let condition: String
    let `operator`: String
    let value: String

    init(response: [String: Any]) throws {
        self.condition = try response.apiGet(key: "condition")
        self.`operator` = try response.apiGet(key: "operator")
        self.value = try response.apiGet(key: "value")
    }
}
