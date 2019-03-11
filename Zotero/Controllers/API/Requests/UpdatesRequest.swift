//
//  UpdatesRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 11/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct UpdatesRequest: ApiRequest {
    let libraryType: SyncController.Library
    let objectType: SyncController.Object
    let params: [[String: Any]]

    var path: String {
        return "\(self.libraryType.apiPath)/\(self.objectType.apiPath)"
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
}
