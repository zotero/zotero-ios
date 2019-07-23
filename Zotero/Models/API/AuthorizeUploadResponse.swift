//
//  AuthorizeUploadResponse.swift
//  Zotero
//
//  Created by Michal Rentka on 18/07/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum AuthorizeUploadResponseError: Error {
    case notDictionary, missingKeys
}

enum AuthorizeUploadResponse {
    case exists
    case new(AuthorizeNewUploadResponse)

    init(from jsonObject: Any) throws {
        guard let data = jsonObject as? [String: Any] else {
            throw AuthorizeUploadResponseError.notDictionary
        }

        if data["exists"] != nil {
            self = .exists
        } else {
            self = try .new(AuthorizeNewUploadResponse(from: data))
        }
    }
}

struct AuthorizeNewUploadResponse {
    let url: URL
    let uploadKey: String
    let params: [String: String]

    init(from jsonObject: [String: Any]) throws {
        guard let urlString = jsonObject["url"] as? String,
              let url = URL(string: urlString.replacingOccurrences(of: "\\", with: "")),
              let uploadKey = jsonObject["uploadKey"] as? String,
              let params = jsonObject["params"] as? [String: String] else {
            throw AuthorizeUploadResponseError.missingKeys
        }

        self.url = url
        self.uploadKey = uploadKey
        self.params = params
    }
}
