//
//  CollectionResponse.swift
//  Zotero
//
//  Created by Michal Rentka on 08/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct CollectionResponse: KeyedResponse {
    struct Data {
        let name: String
        let parentCollection: String?
    }

    let key: String
    let library: LibraryResponse
    let links: LinksResponse?
    let data: CollectionResponse.Data
    let version: Int

    init(response: [String: Any]) throws {
        let library: [String: Any] = try response.apiGet(key: "library")
        let data: [String: Any] = try response.apiGet(key: "data")
        let key: String = try response.apiGet(key: "key")

        self.key = key
        self.library = try LibraryResponse(response: library)
        self.links = try (response["links"] as? [String: Any]).flatMap({ try LinksResponse(response: $0) })
        self.version = try response.apiGet(key: "version")
        self.data = try Data(response: data, key: key)
    }
}

extension CollectionResponse.Data {
    init(response: [String: Any], key: String) throws {
        // Check for unknown fields
        if let unknownKey = response.keys.first(where: { !FieldKeys.Collection.knownDataKeys.contains($0) }) {
            throw SchemaError.unknownField(key: key, field: unknownKey)
        }

        self.name = try response.apiGet(key: "name")
        self.parentCollection = response["parentCollection"] as? String
    }
}
