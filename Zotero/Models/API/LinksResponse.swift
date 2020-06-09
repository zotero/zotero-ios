//
//  LinksResponse.swift
//  Zotero
//
//  Created by Michal Rentka on 08/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct LinksResponse: Codable {
    let `self`: LinkResponse?
    let alternate: LinkResponse?
    let up: LinkResponse?
    let enclosure: LinkResponse?
}

struct LinkResponse: Codable {
    let href: String
    let type: String
    let title: String?
    let length: Int?
}
