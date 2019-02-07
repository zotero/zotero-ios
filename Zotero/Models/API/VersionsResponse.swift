//
//  VersionsResponse.swift
//  Zotero
//
//  Created by Michal Rentka on 07/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct VersionsResponse<Key: Decodable&Hashable> {
    let versions: [Key: Int]

    var responseHeaders: [AnyHashable : Any]
}

extension VersionsResponse: ApiResponse {
    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let versions = try container.decode([Key: Int].self)
        self.init(versions: versions, responseHeaders: [:])
    }
}
