//
//  LinksResponse.swift
//  Zotero
//
//  Created by Michal Rentka on 08/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct LinksResponse {
    let main: LinkResponse?
    let alternate: LinkResponse?
}

extension LinksResponse: Decodable {
    private enum Keys: String, CodingKey {
        case main
        case alternate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: LinksResponse.Keys.self)
        let main = try container.decodeIfPresent(LinkResponse.self, forKey: .main)
        let alternate = try container.decodeIfPresent(LinkResponse.self, forKey: .alternate)
        self.init(main: main, alternate: alternate)
    }
}

struct LinkResponse: Decodable {
    let href: String
    let type: String
}
