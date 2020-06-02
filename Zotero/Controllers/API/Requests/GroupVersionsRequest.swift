//
//  GroupVersionsRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 02/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct GroupVersionsRequest: ApiResponseRequest {
    typealias Response = [Int: Int]

    let userId: Int

    var endpoint: ApiEndpoint {
        return .zotero(path: "users/\(self.userId)/groups")
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

    var headers: [String : String]? {
        return nil
    }
}
