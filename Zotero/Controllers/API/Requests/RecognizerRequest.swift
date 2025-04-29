//
//  RecognizerRequest.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 24/2/25.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct RecognizerRequest: ApiResponseRequest {
    typealias Response = RemoteRecognizerResponse
    let parameters: [String: Any]?

    var endpoint: ApiEndpoint { .other(URL(string: "https://services.zotero.org/recognizer/recognize")!) }
    var httpMethod: ApiHttpMethod { .post }
    var encoding: ApiParameterEncoding { .json }
    var headers: [String: String]? { nil }

    init(parameters: [String: Any]) {
        self.parameters = parameters
    }
}
