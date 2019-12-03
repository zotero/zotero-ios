//
//  FileRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 20/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct FileRequest: ApiDownloadRequest {
    enum EndpointData {
        case `internal`(LibraryIdentifier, Int, String)
        case external(URL)
    }

    let data: EndpointData
    let destination: File

    var endpoint: ApiEndpoint {
        switch self.data {
        case .external(let url):
            return .other(url)
        case .internal(let libraryId, let userId, let key):
            return .zotero(path: "\(libraryId.apiPath(userId: userId))/items/\(key)/file")
        }
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
