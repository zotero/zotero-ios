//
//  AttachmentUploadRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 18/07/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct AttachmentUploadRequest: ApiRequest {
    let url: URL
    let md5: String

    var endpoint: ApiEndpoint {
        return .other(self.url)
    }

    var httpMethod: ApiHttpMethod {
        return .post
    }

    var parameters: [String : Any]? {
        return nil
    }

    var encoding: ApiParameterEncoding {
        return .url
    }

    var headers: [String : String]? {
        return ["If-None-Match": "*",
                "md5": self.md5]
    }
}
