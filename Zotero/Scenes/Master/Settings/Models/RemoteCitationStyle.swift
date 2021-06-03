//
//  RemoteCitationStyle.swift
//  Zotero
//
//  Created by Michal Rentka on 19.05.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct RemoteCitationStyle: Identifiable {
    let title: String
    let name: String
    let dependent: Bool
    let category: RemoteCitationStyleCategory
    let updated: Date
    let href: String

    var id: String {
        return self.name
    }
}

extension RemoteCitationStyle: Decodable {
    private enum CodingKeys: String, CodingKey {
        case title, name, dependent, categories, updated, href
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawDate = try container.decode(String.self, forKey: .updated)

        self.title = try container.decode(String.self, forKey: .title)
        self.name = try container.decode(String.self, forKey: .name)
        self.href = try container.decode(String.self, forKey: .href)
        self.dependent = try container.decode(Int.self, forKey: .dependent) == 1
        self.category = try container.decode(RemoteCitationStyleCategory.self, forKey: .categories)
        self.updated = Formatter.sqlFormat.date(from: rawDate) ?? Date(timeIntervalSince1970: 0)
    }
}

struct RemoteCitationStyleCategory: Decodable {
    let format: String
    let fields: [String]
}
