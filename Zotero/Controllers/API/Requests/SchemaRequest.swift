//
//  SchemaRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 08/04/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct SchemaRequest: ApiRequest {
    let etag: String?

    var path: String {
        return "schema"
    }

    var httpMethod: ApiHttpMethod {
        return .get
    }

    var encoding: ApiParameterEncoding {
        return .url
    }

    var parameters: [String : Any]? {
        return nil
    }

    var headers: [String : String]? {
        if let etag = self.etag {
            return ["If-None-Match": etag]
        }
        return nil
    }
}
