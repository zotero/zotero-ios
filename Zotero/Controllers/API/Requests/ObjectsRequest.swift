//
//  ObjectsRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 07/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct ObjectsRequest: ApiRequest {
    let libraryType: SyncController.Library
    let objectType: SyncController.Object
    let keys: String

    var endpoint: ApiEndpoint {
        if self.objectType == .group {
            return .zotero(path: "groups/\(self.keys)")
        }
        return .zotero(path: "\(self.libraryType.apiPath)/\(self.objectType.apiPath)")
    }

    var httpMethod: ApiHttpMethod {
        return .get
    }

    var encoding: ApiParameterEncoding {
        return .url
    }

    var parameters: [String : Any]? {
        switch self.objectType {
        case .group:
            return nil
        case .collection:
            return ["collectionKey": self.keys]
        case .item, .trash:
            return ["itemKey": self.keys]
        case .search:
            return ["searchKey": self.keys]
        case .tag:
            return nil
        }
    }

    var headers: [String : String]? {
        return nil
    }
}
