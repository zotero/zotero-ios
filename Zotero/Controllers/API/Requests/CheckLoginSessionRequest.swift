//
//  CheckLoginSessionRequest.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 21/03/2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct CheckLoginSessionRequest: ApiResponseRequest {
    typealias Response = CheckLoginSessionResponse

    let token: String

    var endpoint: ApiEndpoint {
        return .zotero(path: "keys/sessions/\(token)")
    }

    var httpMethod: ApiHttpMethod {
        return .get
    }

    var encoding: ApiParameterEncoding {
        return .url
    }

    var parameters: [String: Any]? {
        return nil
    }

    var headers: [String: String]? {
        return nil
    }

    var acceptableStatusCodes: Set<Int> {
        return [200]
    }
}
