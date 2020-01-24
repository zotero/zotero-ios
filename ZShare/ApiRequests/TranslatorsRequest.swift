//
//  TranslatorsRequest.swift
//  ZShare
//
//  Created by Michal Rentka on 24/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct TranslatorsRequest: ApiDownloadRequest {
    var downloadUrl: URL {
        return Files.translatorZip.createUrl()
    }

    var endpoint: ApiEndpoint {
        return .other(URL(string: "https://github.com/zotero/translators/archive/master.zip")!)
    }

    var httpMethod: ApiHttpMethod {
        return .get
    }

    var encoding: ApiParameterEncoding {
        return .url
    }

    var headers: [String : String]?
    var parameters: [String : Any]?
}
