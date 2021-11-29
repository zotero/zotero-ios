//
//  AttachmentUploadRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 18/07/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct AttachmentUploadRequest: ApiRequest {
    let endpoint: ApiEndpoint
    let httpMethod: ApiHttpMethod
    let headers: [String : String]?
    let logParams: ApiLogParameters

    init(endpoint: ApiEndpoint, httpMethod: ApiHttpMethod, headers: [String: String]? = nil, logParams: ApiLogParameters = []) {
        self.endpoint = endpoint
        self.httpMethod = httpMethod
        self.headers = headers
        self.logParams = logParams
    }

    var parameters: [String : Any]? {
        return nil
    }

    var encoding: ApiParameterEncoding {
        return .url
    }
}
