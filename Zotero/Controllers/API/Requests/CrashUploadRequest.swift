//
//  CrashUploadRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 18/11/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct CrashUploadRequest: ApiRequest {
    let crashLog: String
    let deviceInfo: String

    var endpoint: ApiEndpoint {
        return .other(URL(string: "https://repo.zotero.org/repo/report")!)
    }

    var httpMethod: ApiHttpMethod {
        return .post
    }

    var parameters: [String : Any]? {
        return ["error": 1,
                "errorData": self.crashLog,
                "diagnostic": self.deviceInfo]
    }

    var encoding: ApiParameterEncoding {
        return .url
    }

    var headers: [String : String]? {
        return nil
    }
}
