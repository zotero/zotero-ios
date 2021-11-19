//
//  ApiLogParameters.swift
//  Zotero
//
//  Created by Michal Rentka on 19.11.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct ApiLogParameters: OptionSet {
    typealias RawValue = Int8

    let rawValue: Int8

    init(rawValue: Int8) {
        self.rawValue = rawValue
    }

    static let headers = ApiLogParameters(rawValue: 1 << 0)
    static let response = ApiLogParameters(rawValue: 1 << 1)
}
