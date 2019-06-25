//
//  KeyRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 24/06/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct KeyRequest: ApiRequest {
    var path: String {
        return "keys/current"
    }

    var httpMethod: ApiHttpMethod {
        return .get
    }

    var encoding: ApiParameterEncoding {
        return .json
    }

    var parameters: [String : Any]? { return nil }

    var headers: [String : String]? { return nil }
}
