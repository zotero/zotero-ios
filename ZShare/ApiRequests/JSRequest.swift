//
//  JSRequest.swift
//  ZShare
//
//  Created by Michal Rentka on 17/12/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct JSRequest: ApiRequest {
    let endpoint: ApiEndpoint
    let httpMethod: ApiHttpMethod
    let encoding: ApiParameterEncoding
    let parameters: [String : Any]?
    let headers: [String : String]?

    init?(options: [String: Any]) {
        guard let urlString = options["url"] as? String,
              let url = URL(string: urlString),
              let methodString = options["method"] as? String,
              let method = ApiHttpMethod(rawValue: methodString),
              let headers = options["headers"] as? [String: String],
              let parameters = options["parameters"] as? [String: Any] else { return nil }

        self.endpoint = .other(url)
        self.httpMethod = method
        self.encoding = .url
        self.headers = headers
        self.parameters = parameters
    }
}
