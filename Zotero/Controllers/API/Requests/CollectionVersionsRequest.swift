//
//  CollectionVersionsRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 04/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct CollectionVersionsRequest: ApiRequest {
    typealias Response = [Int: Int]

    let version: Int

    var path: String {
        return "user/collections"
    }

    var httpMethod: ApiHttpMethod {
        return .get
    }

    var encoding: ApiParameterEncoding {
        return .url
    }

    var parameters: [String : Any]? {
        return ["since": self.version,
                "format": "versions"]
    }
}
