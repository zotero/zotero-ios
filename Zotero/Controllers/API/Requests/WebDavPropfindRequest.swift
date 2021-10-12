//
//  WebDavPropfindRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 12.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct WebDavPropfindRequest: ApiRequest {
    let endpoint: ApiEndpoint
    let httpMethod: ApiHttpMethod
    let parameters: [String : Any]?
    let encoding: ApiParameterEncoding
    let headers: [String : String]?
    let acceptableStatusCodes: Set<Int>

    init(url: URL) {
        self.endpoint = .other(url)
        self.httpMethod = .propfind
        // IIS 5.1 requires at least one property in PROPFIND
        self.parameters = "<propfind xmlns='DAV:'><prop><getcontentlength/></prop></propfind>".data(using: .utf8)?.asParameters()
        self.encoding = .data
        self.headers = ["Content-Type": "text/xml; charset=utf-8", "Depth": "0"]
        self.acceptableStatusCodes = [207, 404]
    }
}
