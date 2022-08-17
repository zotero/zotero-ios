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
        guard let storage = self.configuration.httpCookieStorage else { return }

        if let cookies = storage.cookies {
            for cookie in cookies {
                storage.deleteCookie(cookie)
            }
        }

        guard let cookies = cookies else { return }

        storage.cookieAcceptPolicy = .always

        for wholeCookie in cookies.split(separator: ";") {
            let split = wholeCookie.trimmingCharacters(in: .whitespaces).split(separator: "=")

            guard split.count == 2, let cookie = HTTPCookie(properties: [.name: split[0], .value: split[1], .domain: domain, .originURL: domain, .path: "/"]) else { continue }

            storage.setCookie(cookie)
        }
    }
}
