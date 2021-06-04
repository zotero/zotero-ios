//
//  RepoRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 26/03/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct RepoRequest: ApiRequest {
    let timestamp: Int
    let version: String
    let type: Int
    let styles: [String: Any]?

    var endpoint: ApiEndpoint {
        return .other(URL(string: "https://repo.zotero.org/repo/updated")!)
    }

    var httpMethod: ApiHttpMethod {
        return .get
    }

    var encoding: ApiParameterEncoding {
        return .jsonAndUrl
    }

    var parameters: [String : Any]? {
        var parameters: [String: Any] = [JsonAndUrlEncoding.urlKey: ["last": self.timestamp,
                                                                     "version": self.version,
                                                                     "m": self.type]]
        if let styles = self.styles {
            parameters[JsonAndUrlEncoding.jsonKey] = styles
        }
        return parameters
    }

    var headers: [String : String]? {
        return nil
    }
}
