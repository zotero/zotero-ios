//
//  AuthorizeUploadResponse.swift
//  Zotero
//
//  Created by Michal Rentka on 18/07/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum AuthorizeUploadResponse: Decodable {
    case exists
    case new(AuthorizeNewUploadResponse)

    private enum Keys: String, CodingKey {
        case url, contentType, prefix, suffix, uploadKey, exists
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)

        if container.contains(.exists) {
            self = .exists
        }

        self = .exists
    }
}

struct AuthorizeNewUploadResponse: Decodable {
    let url: URL
    let contentType: String
    let prefix: String
    let suffix: String
    let uploadKey: String
}
