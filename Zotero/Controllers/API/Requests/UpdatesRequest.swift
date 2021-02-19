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
    let objectType: SyncObject
    let params: [[String: Any]]
    let version: Int?

    var endpoint: ApiEndpoint {
        return .zotero(path: "\(self.libraryId.apiPath(userId: self.userId))/\(self.objectType.apiPath)")
    }

    var httpMethod: ApiHttpMethod {
        return .post
    }

    var encoding: ApiParameterEncoding {
        switch self.objectType {
        case .settings:
            // Settings don't support batched writes, they send single json.
            return .json
        default:
            return .array
        }
    }

    var parameters: [String : Any]? {
        switch self.objectType {
        case .settings:
            // Settings don't support batched writes and they are not generated in batches, the array always contains 1 batch.
            return self.params.first
        default:
            return self.params.asParameters()
        }
    }

    var headers: [String : String]? {
        return self.version.flatMap { ["If-Unmodified-Since-Version": $0.description] }
    }
}
