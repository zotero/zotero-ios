//
//  GroupRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 02/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct GroupRequest: ApiResponseRequest {
    typealias Response = GroupResponse

    let identifier: Int

    var endpoint: ApiEndpoint {
        return .zotero(path: "groups/\(self.identifier)")
    }

    var httpMethod: ApiHttpMethod {
        return .get
    }

    var encoding: ApiParameterEncoding {
        return .url
    }

    var parameters: [String: Any]? {
        return nil
    }

    var headers: [String: String]? {
        return nil
    }
}
