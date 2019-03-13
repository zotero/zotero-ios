//
//  DeletionsRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 21/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct DeletionsRequest: ApiResponseRequest {
    typealias Response = DeletionsResponse

    let libraryType: SyncController.Library
    let version: Int

    var path: String {
        return "\(self.libraryType.apiPath)/deleted"
    }

    var httpMethod: ApiHttpMethod {
        return .get
    }

    var encoding: ApiParameterEncoding {
        return .url
    }

    var parameters: [String : Any]? {
        return ["since": self.version]
    }

    var headers: [String : String]? {
        return nil
    }
}
