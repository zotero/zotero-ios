//
//  WebDavRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 06.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct WebDavRequest: ApiRequest {
    let endpoint: ApiEndpoint
    let httpMethod: ApiHttpMethod
    let parameters: [String : Any]?
    let encoding: ApiParameterEncoding
    let headers: [String : String]?
    let acceptableStatusCodes: Set<Int>

    init(url: URL, httpMethod: ApiHttpMethod, parameters: [String: Any]? = nil, parameterEncoding: ApiParameterEncoding = .url, headers: [String: String]? = nil, acceptableStatusCodes: Set<Int>) {
        self.endpoint = .other(url)
        self.httpMethod = httpMethod
        self.parameters = parameters
        self.encoding = parameterEncoding
        self.headers = headers
        self.acceptableStatusCodes = acceptableStatusCodes
    }
}
