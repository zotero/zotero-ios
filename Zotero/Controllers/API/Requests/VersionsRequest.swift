//
//  VersionsRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 04/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct VersionsRequest: ApiResponseRequest {
    typealias Response = [String: Int]

    let libraryId: LibraryIdentifier
    let userId: Int
    let objectType: SyncObject
    let version: Int?

    var endpoint: ApiEndpoint {
        return .zotero(path: "\(self.libraryId.apiPath(userId: self.userId))/\(self.objectType.apiPath)")
    }

    var httpMethod: ApiHttpMethod {
        return .get
    }

    var encoding: ApiParameterEncoding {
        return .url
    }

    var parameters: [String : Any]? {
        var parameters: [String: Any] = ["format": "versions"]
        if let version = self.version {
            parameters["since"] = version
        }
        return parameters
    }

    var headers: [String : String]? {
        guard let version = self.version else { return nil }
        return ["If-Modified-Since-Version": "\(version)"]
    }
}
