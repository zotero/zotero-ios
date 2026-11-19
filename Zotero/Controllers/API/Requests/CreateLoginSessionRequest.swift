//
//  CreateLoginSessionRequest.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 21/03/2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct CreateLoginSessionRequest: ApiResponseRequest {
    typealias Response = CreateLoginSessionResponse

    var endpoint: ApiEndpoint {
        return .zotero(path: "keys/sessions")
    }

    var httpMethod: ApiHttpMethod {
        return .post
    }

    var encoding: ApiParameterEncoding {
        return .json
    }

    let parameters: [String: Any]?

    let headers: [String: String]?

    var acceptableStatusCodes: Set<Int> {
        return [201]
    }

    init(userId: Int? = nil, apiKey: String? = nil) {
        parameters = userId.flatMap({ ["userID": $0] })
        headers = apiKey.flatMap({ ["Zotero-API-Key": $0] })
    }
}
