//
//  WebDavDownloadRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 12.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct WebDavDownloadRequest: ApiRequest {
    let endpoint: ApiEndpoint
    let httpMethod: ApiHttpMethod
    let parameters: [String : Any]?
    let encoding: ApiParameterEncoding
    let headers: [String : String]?
    let acceptableStatusCodes: Set<Int>

    init(url: URL) {
        self.endpoint = .other(url)
        self.httpMethod = .get
        self.parameters = nil
        self.encoding = .url
        self.headers = nil
        self.acceptableStatusCodes = [200, 404]
    }

    init(endpoint: ApiEndpoint) {
        self.endpoint = endpoint
        self.httpMethod = .get
        self.parameters = nil
        self.encoding = .url
        self.headers = nil
        self.acceptableStatusCodes = [200, 404]
    }
}
