//
//  GroupResponse.swift
//  Zotero
//
//  Created by Michal Rentka on 05/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct GroupResponse {
    struct Data: Decodable {
        let name: String
        let owner: Int
        let type: String
        let description: String
        let libraryEditing: String
        let libraryReading: String
        let fileEditing: String
    }

    let identifier: Int
    let version: Int
    let data: GroupResponse.Data
}

extension GroupResponse: Decodable {
    enum Keys: String, CodingKey {
        case identifier = "id"
        case data, version
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        let identifier = try container.decode(Int.self, forKey: .identifier)
        let version = try container.decode(Int.self, forKey: .version)
        let data = try container.decode(GroupResponse.Data.self, forKey: .data)
        self.init(identifier: identifier, version: version, data: data)
    }
}
