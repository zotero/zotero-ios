//
//  ItemResponse.swift
//  Zotero
//
//  Created by Michal Rentka on 08/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct ItemResponse {
    struct Data {
        let itemType: String
        let title: String
        let parentItem: String?
        let collections: [String]?
        let isTrash: Bool
    }

    let identifier: String
    let library: LibraryResponse
    let links: LinksResponse
    let data: ItemResponse.Data
    let version: Int
}

extension ItemResponse: Decodable {
    private enum Keys: String, CodingKey {
        case identifier = "key"
        case version, library, links, data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ItemResponse.Keys.self)
        let identifier = try container.decode(String.self, forKey: .identifier)
        let library = try container.decode(LibraryResponse.self, forKey: .library)
        let links = try container.decode(LinksResponse.self, forKey: .links)
        let data = try container.decode(ItemResponse.Data.self, forKey: .data)
        let version = try container.decode(Int.self, forKey: .version)
        self.init(identifier: identifier, library: library, links: links, data: data, version: version)
    }
}

extension ItemResponse.Data: Decodable {
    private enum Keys: String, CodingKey {
        case itemType, title, parentItem, collections, deleted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ItemResponse.Data.Keys.self)
        let itemType = try container.decode(String.self, forKey: .itemType)
        let title = try container.decode(String.self, forKey: .title)
        let parentItem = try container.decodeIfPresent(String.self, forKey: .parentItem)
        let collections = try container.decodeIfPresent([String].self, forKey: .collections)
        let deleted = try container.decodeIfPresent(Int.self, forKey: .deleted)
        self.init(itemType: itemType, title: title, parentItem: parentItem,
                  collections: collections, isTrash: (deleted == 1))
    }
}
