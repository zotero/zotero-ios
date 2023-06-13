//
//  RegisterUploadRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 19/07/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct RegisterUploadRequest: ApiRequest {
    let libraryId: LibraryIdentifier
    let userId: Int
    let key: String
    let uploadKey: String
    let oldMd5: String?

    var endpoint: ApiEndpoint {
        return .zotero(path: "\(self.libraryId.apiPath(userId: self.userId))/items/\(self.key)/file")
    }

    var httpMethod: ApiHttpMethod {
        return .post
    }

    var encoding: ApiParameterEncoding {
        return .url
    }

    var parameters: [String: Any]? {
        return ["upload": self.uploadKey]
    }

    var headers: [String: String]? {
        if let md5 = self.oldMd5 {
            return ["If-Match": md5]
        }
        return ["If-None-Match": "*"]
    }
}
