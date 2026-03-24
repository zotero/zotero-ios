//
//  SubmitDeletionsRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 06/05/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct SubmitDeletionsRequest: ApiRequest {
    let libraryId: LibraryIdentifier
    let userId: Int
    let objectType: SyncObject
    let keys: [String]
    let version: Int

    var endpoint: ApiEndpoint {
        return .zotero(path: "\(libraryId.apiPath(userId: userId))/\(objectType.apiPath)")
    }

    var httpMethod: ApiHttpMethod {
        return .delete
    }

    var encoding: ApiParameterEncoding {
        return .url
    }

    var parameters: [String: Any]? {
        let joinedKeys = keys.joined(separator: ",")
        switch objectType {
        case .collection:
            return ["collectionKey": joinedKeys]

        case .item, .trash:
            return ["itemKey": joinedKeys]

        case .search:
            return ["searchKey": joinedKeys]

        case .settings:
            return ["settingKey": joinedKeys]
        }
    }

    var headers: [String: String]? {
        return ["If-Unmodified-Since-Version": version.description]
    }
}
