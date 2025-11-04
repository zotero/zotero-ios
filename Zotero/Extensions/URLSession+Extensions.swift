//
//  URLSession+Extensions.swift
//  Zotero
//
//  Created by Michal Rentka on 17.08.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

extension URLSession {
    func set(cookies: String?, domain: String) {
        guard let storage = configuration.httpCookieStorage else { return }
        storage.cookieAcceptPolicy = .always
        let newCookies: [HTTPCookie] = cookies?.split(separator: ";").compactMap({
            let parts = $0.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            return HTTPCookie(properties: [.name: parts[0], .value: parts[1], .domain: domain, .originURL: domain, .path: "/"])
        }) ?? []
        guard !newCookies.isEmpty else { return }
        let existingCookies = storage.cookies ?? []
        for cookie in newCookies {
            existingCookies
                .filter({ $0.name.caseInsensitiveCompare(cookie.name) == .orderedSame && $0.domain == cookie.domain && $0.path == cookie.path })
                .forEach({ storage.deleteCookie($0) })
            storage.setCookie(cookie)
        }
    }
}
