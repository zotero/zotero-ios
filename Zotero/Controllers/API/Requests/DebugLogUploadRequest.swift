//
//  DebugLogUploadRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 01.03.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct DebugLogUploadRequest: ApiRequest {
    var endpoint: ApiEndpoint {
        return .other(URL(string: "https://repo.zotero.org/repo/report?debug=1")!)
    }

    var httpMethod: ApiHttpMethod {
        return .post
    }

    var parameters: [String : Any]? {
        return nil
    }

    var encoding: ApiParameterEncoding {
        return .url
    }

    var headers: [String : String]? {
        return nil
    }
}
