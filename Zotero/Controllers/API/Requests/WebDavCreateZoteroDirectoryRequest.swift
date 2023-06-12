//
//  WebDavCreateZoteroDirectoryRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 26.11.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct WebDavCreateZoteroDirectoryRequest: ApiRequest {
    let endpoint: ApiEndpoint
    let httpMethod: ApiHttpMethod
    let parameters: [String: Any]?
    let encoding: ApiParameterEncoding
    let headers: [String: String]?
    let acceptableStatusCodes: Set<Int>
    let logParams: ApiLogParameters

    init(url: URL) {
        self.endpoint = .webDav(url)
        self.httpMethod = .mkcol
        self.parameters = nil
        self.encoding = .url
        self.headers = nil
        self.acceptableStatusCodes = [200, 201, 204]
        self.logParams = .headers
    }
}
