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
        let isTrash: Bool
    }

    let key: String
    let library: LibraryResponse
    let links: LinksResponse?
    let data: SearchResponse.Data
    let version: Int

    init(response: [String: Any]) throws {
        let key: String = try response.apiGet(key: "key", errorLogMessage: "SearchResponse missing key \"key\"")
        let library: [String: Any] = try response.apiGet(key: "library", errorLogMessage: "SearchResponse missing key \"library\"")
        let data: [String: Any] = try response.apiGet(key: "data", errorLogMessage: "SearchResponse missing key \"data\"")

        self.key = key
        self.library = try LibraryResponse(response: library)
        self.links = try (response["links"] as? [String: Any]).flatMap { try LinksResponse(response: $0) }
        self.version = try response.apiGet(key: "version", errorLogMessage: "SearchResponse missing key \"version\"")
        self.data = try Data(response: data, key: key)
    }
}

extension SearchResponse.Data {
    init(response: [String: Any], key: String) throws {
        // Check for unknown fields
        if let unknownKey = response.keys.first(where: { !FieldKeys.Search.knownDataKeys.contains($0) }) {
            throw SchemaError.unknownField(key: key, field: unknownKey)
        }

        let conditions: [[String: Any]] = try response.apiGet(key: "conditions", errorLogMessage: "SearchResponse.Data missing key \"conditions\"")

        self.name = try response.apiGet(key: "name", errorLogMessage: "SearchResponse.Data missing key \"name\"")
        self.conditions = try conditions.map({ try ConditionResponse(response: $0) })
        self.isTrash = (response["deleted"] as? Bool) ?? ((response["deleted"] as? Int) == 1)
    }
}

struct ConditionResponse {
    let condition: String
    let `operator`: String
    let value: String

    init(response: [String: Any]) throws {
        self.condition = try response.apiGet(key: "condition", errorLogMessage: "ConditionResponse missing key \"condition\"")
        self.`operator` = try response.apiGet(key: "operator", errorLogMessage: "ConditionResponse missing key \"operator\"")
        self.value = try response.apiGet(key: "value", errorLogMessage: "ConditionResponse missing key \"value\"")
    }
}
