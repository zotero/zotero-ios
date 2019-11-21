//
//  AuthorizeUploadRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 18/07/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct AuthorizeUploadRequest: ApiRequest {
    let libraryType: SyncController.Library
    let key: String
    let filename: String
    let filesize: UInt64
    let md5: String
    let mtime: Int

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
        return ["filename": self.filename,
                "filesize": self.filesize,
                "md5": self.md5,
                "mtime": self.mtime]
    }

    var headers: [String : String]? {
        return ["If-None-Match": "*"]
    }
}
