//
//  FileRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 20/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct FileRequest: ApiDownloadRequest {
    let endpoint: ApiEndpoint
    let destination: File

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

    var downloadUrl: URL {
        return self.destination.createUrl()
    }

    init(libraryId: LibraryIdentifier, userId: Int, key: String, destination: File) {
        self.endpoint = .zotero(path: "\(libraryId.apiPath(userId: userId))/items/\(key)/file")
        self.destination = destination
    }

    init(webDavUrl url: URL, destination: File) {
        self.endpoint = .webDav(url)
        self.destination = destination
    }

    init(url: URL, destination: File) {
        self.endpoint = .other(url)
        self.destination = destination
    }
}
