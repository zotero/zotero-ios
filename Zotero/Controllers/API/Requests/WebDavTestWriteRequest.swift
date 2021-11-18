//
//  WebDavTestWriteRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 12.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct WebDavTestWriteRequest: ApiRequest {
    let endpoint: ApiEndpoint
    let httpMethod: ApiHttpMethod
    let parameters: [String : Any]?
    let encoding: ApiParameterEncoding
    let headers: [String : String]?
    let acceptableStatusCodes: Set<Int>

    init(url: URL) {
        self.endpoint = .webDav(url.appendingPathComponent("zotero-test-file.prop"))
        self.httpMethod = .put
        self.parameters = " ".data(using: .utf8)?.asParameters()
        self.encoding = .data
        self.headers = nil
        self.acceptableStatusCodes = [200, 201, 204]
    }
}
