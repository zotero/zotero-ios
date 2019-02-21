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

    let groupType: SyncGroupType
    let version: Int

    var path: String {
        return "\(self.groupType.apiPath)/deleted"
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
}
