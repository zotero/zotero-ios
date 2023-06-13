//
//  ObjectsRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 07/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct ObjectsRequest: ApiRequest {
    let libraryId: LibraryIdentifier
    let userId: Int
    let objectType: SyncObject
    let keys: String

    var endpoint: ApiEndpoint {
        return .zotero(path: "\(self.libraryId.apiPath(userId: self.userId))/\(self.objectType.apiPath)")
    }

    var httpMethod: ApiHttpMethod {
        return .get
    }

    var encoding: ApiParameterEncoding {
        return .url
    }

    var parameters: [String: Any]? {
        switch self.objectType {
        case .collection:
            return ["collectionKey": self.keys]

        case .item, .trash:
            return ["itemKey": self.keys]

        case .search:
            return ["searchKey": self.keys]

        case .settings:
            return nil
        }
    }

    var headers: [String: String]? {
        return nil
    }

    var logParams: ApiLogParameters {
        return .response
    }
}
