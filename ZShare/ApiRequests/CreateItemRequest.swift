//
//  CreateItemRequest.swift
//  ZShare
//
//  Created by Michal Rentka on 02/12/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct CreateItemRequest: ApiRequest {
    let libraryId: LibraryIdentifier
    let key: String
    let userId: Int

    var endpoint: ApiEndpoint {
        return .zotero(path: "\(self.libraryId.apiPath(userId: self.userId))/items/\(self.key)")
    }

    var httpMethod: ApiHttpMethod {
        return .put
    }

    var encoding: ApiParameterEncoding {
        return .json
    }

    let parameters: [String: Any]?

    var headers: [String: String]? {
        return ["If-Unmodified-Since-Version": "0"]
    }
}
