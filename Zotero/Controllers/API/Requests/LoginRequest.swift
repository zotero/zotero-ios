//
//  LoginRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct LoginRequest: ApiRequest {
    typealias Response = LoginResponse

    var path: String {
        return "keys"
    }

    var httpMethod: ApiHttpMethod {
        return .post
    }

    var encoding: ApiParameterEncoding {
        return .json
    }

    var parameters: [String : Any]?

    init(username: String, password: String) {
        self.parameters = ["username": username,
                           "password": password,
                           "name": "Automatic Zotero iOS Client Key",
                           "access": ["user": ["library": true,
                                               "notes": true,
                                               "write": true,
                                               "files": true],
                                      "groups": ["all": ["library": true,
                                                         "write": true]]]]
    }
}
