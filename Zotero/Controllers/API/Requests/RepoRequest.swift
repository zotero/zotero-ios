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
    let styles: [Style]?

    var endpoint: ApiEndpoint {
        return .other(URL(string: "https://repo.zotero.org/repo/updated?m=\(self.type)&last=\(self.timestamp)&version=\(self.version)")!)
    }

    var httpMethod: ApiHttpMethod {
        return .post
    }

    var encoding: ApiParameterEncoding {
        return .url
    }

    var parameters: [String : Any]? {
        guard let styles = self.styles else { return nil }

        let styleParameters = styles.map({ style -> [String: Any] in
            return ["id": style.identifier,
                    "updated": Int(style.updated.timeIntervalSince1970),
                    "url": style.href.absoluteString]
        })

        if let data = try? JSONSerialization.data(withJSONObject: styleParameters), let jsonString = String(data: data, encoding: .utf8) {
            return ["styles": jsonString]
        }

        return nil
    }

    var headers: [String : String]? {
        return nil
    }
}
