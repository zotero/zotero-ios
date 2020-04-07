//
//  TranslatorsRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 26/03/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct TranslatorsRequest: ApiRequest {
    let timestamp: Int
    let version: String
    let type: Int

    var endpoint: ApiEndpoint {
        return .other(URL(string: "https://repo.zotero.org/repo/updated")!)
    }

    var httpMethod: ApiHttpMethod {
        return .get
    }

    var encoding: ApiParameterEncoding {
        return .url
    }

    var parameters: [String : Any]? {
        return ["last": self.timestamp,
                "version": self.version,
                "m": self.type]
    }

    var headers: [String : String]? {
        return nil
    }
}
