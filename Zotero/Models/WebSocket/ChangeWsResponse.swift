//
//  ChangeWsResponse.swift
//  Zotero
//
//  Created by Michal Rentka on 04.02.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct ChangeWsResponse {
    enum Error: Swift.Error {
        case unknownLibrary(String)
    }

    let libraryId: LibraryIdentifier
}

extension ChangeWsResponse: Decodable {
    enum Keys: String, CodingKey {
        case topic = "topic"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        let topic = try container.decode(String.self, forKey: .topic)

        guard let libraryId = LibraryIdentifier.from(apiPath: topic) else {
            throw ChangeWsResponse.Error.unknownLibrary(topic)
        }

        self.init(libraryId: libraryId)
    }
}
