//
//  GroupResponse.swift
//  Zotero
//
//  Created by Michal Rentka on 05/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct GroupResponse {
    let identifier: Int
    let version: Int
    let data: GroupDataResponse

    var responseHeaders: [AnyHashable : Any]
}

struct GroupDataResponse: Decodable {
    let name: String
    let owner: Int
    let type: String
    let description: String
    let libraryEditing: String
    let libraryReading: String
    let fileEditing: String
}

extension GroupResponse: ApiResponse {
    enum Keys: String, CodingKey {
        case identifier = "id"
        case data
        case version
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        let identifier = try container.decode(Int.self, forKey: .identifier)
        let version = try container.decode(Int.self, forKey: .version)
        let data = try container.decode(GroupDataResponse.self, forKey: .data)
        self.init(identifier: identifier, version: version, data: data, responseHeaders: [:])
    }
}
