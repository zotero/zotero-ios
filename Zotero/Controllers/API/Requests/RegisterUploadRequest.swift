//
//  RegisterUploadRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 19/07/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct RegisterUploadRequest: ApiRequest {
    let libraryType: SyncController.Library
    let key: String
    let uploadKey: String

    var endpoint: ApiEndpoint {
        return .zotero(path: "\(self.libraryType.apiPath)/items/\(self.key)/file")
    }

    var httpMethod: ApiHttpMethod {
        return .post
    }

    var encoding: ApiParameterEncoding {
        return .url
    }

    var parameters: [String : Any]? {
        return ["upload": self.uploadKey]
    }

    var headers: [String : String]? {
        return ["If-None-Match": "*"]
    }
}
