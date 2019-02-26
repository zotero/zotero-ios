//
//  SettingsResponse.swift
//  Zotero
//
//  Created by Michal Rentka on 26/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct SettingsResponse: Decodable {
    let tagColors: TagColorsResponse?
}

struct TagColorsResponse: Decodable {
    let value: [TagColorResponse]
    let version: Int
}

struct TagColorResponse: Decodable {
    let name: String
    let color: String
}
