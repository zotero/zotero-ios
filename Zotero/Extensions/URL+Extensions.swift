//
//  URL+Extensions.swift
//  Zotero
//
//  Created by Michal Rentka on 14.10.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

extension URL {
    var withHttpSchemeIfMissing: URL {
        if self.scheme == "http" || self.scheme == "https" {
            return self
        }

        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: true) else { return self }
        components.scheme = "http"
        return components.url ?? self
    }

    func appendingQueryItem(name: String, value: String) -> URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return nil }
        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: name, value: value))
        components.queryItems = queryItems
        return components.url
    }
}
