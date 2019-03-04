//
//  SettingsRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 26/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct SettingsRequest: ApiResponseRequest {
    typealias Response = SettingsResponse

    let libraryType: SyncLibraryType
    let version: Int?

    var path: String {
        return "\(self.libraryType.apiPath)/settings"
    }

    var httpMethod: ApiHttpMethod {
        return .get
    }

    var encoding: ApiParameterEncoding {
        return .url
    }

    var parameters: [String : Any]? {
        guard let version = self.version else { return nil }
        return ["since": version]
    }
}
