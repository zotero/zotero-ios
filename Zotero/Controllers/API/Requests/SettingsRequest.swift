//
//  SettingsRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 26/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct SettingsRequest: ApiRequest {
    let libraryId: LibraryIdentifier
    let userId: Int
    let version: Int

    var endpoint: ApiEndpoint {
        return .zotero(path: "\(self.libraryId.apiPath(userId: self.userId))/settings")
    }

    var httpMethod: ApiHttpMethod {
        return .get
    }

    var encoding: ApiParameterEncoding {
        return .url
    }

    var parameters: [String: Any]? {
        return ["since": self.version]
    }

    var headers: [String: String]? {
        return ["If-Modified-Since-Version": "\(self.version)"]
    }
}
