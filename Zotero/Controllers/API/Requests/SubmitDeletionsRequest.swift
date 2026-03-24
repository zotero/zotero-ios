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
        return .zotero(path: "\(self.libraryId.apiPath(userId: self.userId))/\(self.objectType.apiPath)")
    }

    var httpMethod: ApiHttpMethod {
        return .delete
    }

    var encoding: ApiParameterEncoding {
        return .url
    }

    var parameters: [String: Any]? {
        switch self.objectType {
        case .collection:
            return ["collectionKey": keys.joined(separator: ",")]

        case .item, .trash:
            return ["itemKey": keys.joined(separator: ",")]

        case .search:
            return ["searchKey": keys.joined(separator: ",")]

        case .settings:
            let joinedKeys = keys.map({ SettingKeyParser.uid(fromKey: $0, libraryId: libraryId, prefix: "lastRead") }).joined(separator: ",")
            return ["settingKey": joinedKeys]
        }
    }

    var headers: [String: String]? {
        return ["If-Unmodified-Since-Version": self.version.description]
    }
}
