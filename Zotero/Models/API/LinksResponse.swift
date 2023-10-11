//
//  LinksResponse.swift
//  Zotero
//
//  Created by Michal Rentka on 08/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct LinksResponse {
    let `self`: LinkResponse?
    let alternate: LinkResponse?
    let up: LinkResponse?
    let enclosure: LinkResponse?

    init(response: [String: Any]) throws {
        self.`self` = try (response["self"] as? [String: Any]).flatMap({ try LinkResponse(response: $0) })
        self.alternate = try (response["alternate"] as? [String: Any]).flatMap({ try LinkResponse(response: $0) })
        self.up = try (response["up"] as? [String: Any]).flatMap({ try LinkResponse(response: $0) })
        self.enclosure = try (response["enclosure"] as? [String: Any]).flatMap({ try LinkResponse(response: $0) })
    }
}

struct LinkResponse {
    let href: String
    let type: String?
    let title: String?
    let length: Int?

    init(response: [String: Any]) throws {
        self.href = try response.apiGet(key: "href", caller: Self.self)
        self.type = response["type"] as? String
        self.title = response["title"] as? String
        self.length = response["length"] as? Int
    }
}
