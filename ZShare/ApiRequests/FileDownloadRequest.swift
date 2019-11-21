//
//  FileDownloadRequest.swift
//  ZShare
//
//  Created by Michal Rentka on 21/11/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct FileDownloadRequest: ApiDownloadRequest {
    let url: URL
    let downloadUrl: URL

    var endpoint: ApiEndpoint {
        return .other(self.url)
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
