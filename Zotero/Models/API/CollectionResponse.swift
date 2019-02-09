//
//  CollectionResponse.swift
//  Zotero
//
//  Created by Michal Rentka on 08/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct CollectionResponse {
    struct Data {
        let name: String
        let parentCollection: String?
    }

    let identifier: String
    let library: LibraryResponse
    let links: LinksResponse
    let data: CollectionResponse.Data
    let version: Int
    var responseHeaders: [AnyHashable : Any]
}

extension CollectionResponse: Decodable {
    private enum Keys: String, CodingKey {
        case key, version, library, links, data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CollectionResponse.Keys.self)
        let identifier = try container.decode(String.self, forKey: .key)
        let library = try container.decode(LibraryResponse.self, forKey: .library)
        let links = try container.decode(LinksResponse.self, forKey: .links)
        let data = try container.decode(CollectionResponse.Data.self, forKey: .data)
        let version = try container.decode(Int.self, forKey: .version)
        self.init(identifier: identifier, library: library, links: links,
                  data: data, version: version, responseHeaders: [:])
    }
}

extension CollectionResponse.Data: Decodable {
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
}
