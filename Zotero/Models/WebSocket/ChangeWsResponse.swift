//
//  ChangeWsResponse.swift
//  Zotero
//
//  Created by Michal Rentka on 04.02.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct ChangeWsResponse {
    enum Kind {
        case library(LibraryIdentifier)
        case translators
    }

    enum Error: Swift.Error {
        case unknownChange(String)
    }

    let type: Kind
}

extension ChangeWsResponse: Decodable {
    enum Keys: String, CodingKey {
        case topic = "topic"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        let topic = try container.decode(String.self, forKey: .topic)

        if topic.contains("translators") || topic.contains("styles") {
            self.init(type: .translators)
            return
        }

        if let libraryId = LibraryIdentifier.from(apiPath: topic) {
            self.init(type: .library(libraryId))
            return
        }

        throw ChangeWsResponse.Error.unknownChange(topic)
    }
}
