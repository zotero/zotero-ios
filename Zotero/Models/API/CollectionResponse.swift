//
//  CollectionResponse.swift
//  Zotero
//
//  Created by Michal Rentka on 08/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct CollectionsResponse {
    let collections: [CollectionResponse]
    let errors: [Error]
}

extension CollectionsResponse: Decodable {
    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()

        var collections: [CollectionResponse] = []
        var errors: [Error] = []

        while !container.isAtEnd {
            do {
                let collection = try container.decode(CollectionResponse.self)
                collections.append(collection)
            } catch let error {
                errors.append(error)
            }
        }

        self.init(collections: collections, errors: errors)
    }
}

struct CollectionResponse: Codable, KeyedResponse {
    struct Data {
        let name: String
        let parentCollection: String?
    }

    let key: String
    let library: LibraryResponse
    let links: LinksResponse?
    let data: CollectionResponse.Data
    let version: Int
}

extension CollectionResponse.Data: Codable {
    private enum Keys: String, CodingKey {
        case name, parentCollection
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CollectionResponse.Data.Keys.self)
        let name = try container.decode(String.self, forKey: .name)
        var parent: String?
        // Try to decode this one silently. There is a little catch on backend. When no parent is assigned, the value
        // on backend is "false". When parent is assigned, there is a String identifier.
        // So when I try to decode as String it throws an error about type mismatch. So I just try to parse
        // and if data doesn't match it's not available and stays nil.
        do {
            parent = try container.decodeIfPresent(String.self, forKey: .parentCollection)
        } catch {}
        self.init(name: name, parentCollection: parent)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CollectionResponse.Data.Keys.self)
        try container.encode(self.name, forKey: .name)
        if let parent = self.parentCollection {
            try container.encode(parent, forKey: .parentCollection)
        } else {
            try container.encode(false, forKey: .parentCollection)
        }
    }
}
