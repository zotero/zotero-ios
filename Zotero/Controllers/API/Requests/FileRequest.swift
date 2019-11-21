//
//  FileRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 20/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct FileRequest: ApiDownloadRequest {
    let library: SyncController.Library
    let key: String
    let destination: File

    var endpoint: ApiEndpoint {
        return .zotero(path: "\(self.library.apiPath)/items/\(self.key)/file")
    }

    var httpMethod: ApiHttpMethod {
        return .get
    }

    var encoding: ApiParameterEncoding {
        return .url
    }

    var parameters: [String : Any]? {
        return nil
    }

    var headers: [String : String]? {
        return nil
    }

    var downloadUrl: URL {
        return self.destination.createUrl()
    }
}
