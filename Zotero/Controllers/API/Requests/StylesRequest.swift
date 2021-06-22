//
//  StylesRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 20.05.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct StylesRequest: ApiResponseRequest {
    typealias Response = RemoteStylesResponse

    var endpoint: ApiEndpoint {
        return .other(URL(string: "https://www.zotero.org/styles-files/styles.json")!)
    }

    var httpMethod: ApiHttpMethod {
        return .get
    }

    var parameters: [String : Any]? {
        return nil
    }

    var encoding: ApiParameterEncoding {
        return .url
    }

    var headers: [String : String]? {
        return nil
    }
}
