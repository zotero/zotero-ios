//
//  DeletionsResponse.swift
//  Zotero
//
//  Created by Michal Rentka on 21/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct DeletionsResponse {
    let collections: [String]
    let searches: [String]
    let items: [String]
    let tags: [String]
}

extension DeletionsResponse: Decodable {
    private enum Keys: String, CodingKey {
        case collections, searches, items, tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        let collections = try container.decode([String].self, forKey: .collections)
        let searches = try container.decode([String].self, forKey: .searches)
        let items = try container.decode([String].self, forKey: .items)
        let tags = try container.decode([String].self, forKey: .tags)
        self.init(collections: collections, searches: searches, items: items, tags: tags)
    }
}
