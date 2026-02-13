//
//  CreditsRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 13.02.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct CreditsRequest: ApiResponseRequest {
    typealias Response = CreditsResponse

    var endpoint: ApiEndpoint {
        return .zotero(path: "tts/credits")
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
}
