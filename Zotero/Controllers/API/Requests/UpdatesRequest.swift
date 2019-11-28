//
//  UpdatesRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 11/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct UpdatesRequest: ApiRequest {
    let libraryId: LibraryIdentifier
    let userId: Int
    let objectType: SyncController.Object
    let params: [[String: Any]]
    let version: Int

    var endpoint: ApiEndpoint {
        return .zotero(path: "\(self.libraryId.apiPath(userId: self.userId))/\(self.objectType.apiPath)")
    }

    var httpMethod: ApiHttpMethod {
        return .post
    }

    var encoding: ApiParameterEncoding {
        return .array
    }

    var parameters: [String : Any]? {
        return self.params.asParameters()
    }

    var headers: [String : String]? {
        return ["If-Unmodified-Since-Version": self.version.description]
    }
}
