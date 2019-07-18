//
//  AuthorizeUploadRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 18/07/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct AuthorizeUploadRequest: ApiResponseRequest {
    typealias Response = AuthorizeUploadResponse

    let libraryType: SyncController.Library
    let key: String
    let filename: String
    let filesize: UInt64
    let md5: String?
    let mtime: Int?

    var path: String {
        return "\(self.libraryType.apiPath)/items/\(self.key)/file"
    }

    var httpMethod: ApiHttpMethod {
        return .post
    }

    var encoding: ApiParameterEncoding {
        return .url
    }

    var parameters: [String : Any]? {
        var parameters: [String: Any] = ["filename": self.filename,
                                         "filesize": self.filesize]
        if let value = self.md5 {
            parameters["md5"] = value
        }
        if let value = self.mtime {
            parameters["mtime"] = value
        }
        return parameters
    }

    var headers: [String : String]? {
        return ["If-None-Match": "*"]
    }
}
