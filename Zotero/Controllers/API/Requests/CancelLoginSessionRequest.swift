//
//  CancelLoginSessionRequest.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 23/03/2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct CancelLoginSessionRequest: ApiRequest {
    let token: String

    var endpoint: ApiEndpoint {
        return .zotero(path: "keys/sessions/\(token)")
    }

    var httpMethod: ApiHttpMethod {
        return .delete
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
        return [204]
    }
}
