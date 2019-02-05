//
//  GroupVersionsRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 04/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct GroupVersionsRequest: ApiRequest {
    typealias Response = [Int: Int]

    let userId: Int64

    var path: String {
        return "users/\(self.userId)/groups"
    }

    var httpMethod: ApiHttpMethod {
        return .get
    }

    var encoding: ApiParameterEncoding {
        return .url
    }

    var parameters: [String : Any]? {
        return ["format": "versions"]
    }
}
