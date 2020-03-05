//
//  LoginRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct LoginRequest: ApiResponseRequest {
    typealias Response = LoginResponse

    var endpoint: ApiEndpoint {
        return .zotero(path: "keys")
    }

    var httpMethod: ApiHttpMethod {
        return .post
    }

    var encoding: ApiParameterEncoding {
        return .json
    }

    private(set) var parameters: [String : Any]?

    var headers: [String : String]? {
        return nil
    }

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

    func redact(parameters: [String : Any]) -> [String : Any] {
        var redacted = parameters
        redacted["password"] = "<redacted>"
        return redacted
    }

    func redact(response: String) -> String {
        return KeysResponseProcessor.redact(response: response)
    }
}
