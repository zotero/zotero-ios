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
        let isTrash: Bool
    }

    let key: String
    let library: LibraryResponse
    let links: LinksResponse?
    let data: CollectionResponse.Data
    let version: Int

    init(response: [String: Any]) throws {
        let library: [String: Any] = try response.apiGet(key: "library", caller: Self.self)
        let data: [String: Any] = try response.apiGet(key: "data", caller: Self.self)
        let key: String = try response.apiGet(key: "key", caller: Self.self)

        self.key = key
        self.library = try LibraryResponse(response: library)
        self.links = try (response["links"] as? [String: Any]).flatMap({ try LinksResponse(response: $0) })
        self.version = try response.apiGet(key: "version", caller: Self.self)
        self.data = try Data(response: data, key: key)
    }
}

extension CollectionResponse.Data {
    init(response: [String: Any], key: String) throws {
        // Check for unknown fields
        if let unknownKey = response.keys.first(where: { !FieldKeys.Collection.knownDataKeys.contains($0) }) {
            throw SchemaError.unknownField(key: key, field: unknownKey)
        }

        self.name = try response.apiGet(key: "name", caller: Self.self)
        self.parentCollection = response["parentCollection"] as? String
        self.isTrash = (response["deleted"] as? Bool) ?? ((response["deleted"] as? Int) == 1)
    }
}
