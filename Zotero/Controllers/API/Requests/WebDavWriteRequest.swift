//
//  WebDavWriteRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 21.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct WebDavWriteRequest: ApiRequest {
    let endpoint: ApiEndpoint
    let httpMethod: ApiHttpMethod
    let parameters: [String: Any]?
    let encoding: ApiParameterEncoding
    let headers: [String: String]?
    let acceptableStatusCodes: Set<Int>
    let logParams: ApiLogParameters

    init(url: URL, data: Data) {
        self.endpoint = .webDav(url)
        self.httpMethod = .put
        self.parameters = data.asParameters()
        self.encoding = .data
        self.headers = nil
        self.acceptableStatusCodes = [200, 201, 204]
        self.logParams = .headers
    }
}
