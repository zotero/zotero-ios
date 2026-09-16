//
//  VoicesRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 14.01.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct VoicesRequest: ApiRequest {
    var endpoint: ApiEndpoint {
        return .zotero(path: "tts/voices")
    }

    var httpMethod: ApiHttpMethod {
        return .get
    }

    var encoding: ApiParameterEncoding {
        return .url
    }

    var parameters: [String: Any]? {
        return ["version": 1]
    }

    var headers: [String: String]? {
        return nil
    }
}
