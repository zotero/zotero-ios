//
//  WebDavCredentials.swift
//  ZoteroTests
//
//  Created by Michal Rentka on 27.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

@testable import Zotero

import Foundation

class WebDavCredentials: WebDavSessionStorage {
    var isVerified: Bool
    var isEnabled: Bool
    var username: String
    var url: String
    var scheme: WebDavScheme
    var password: String

    init(username: String, password: String, scheme: WebDavScheme, url: String, isVerified: Bool) {
        self.isEnabled = true
        self.isVerified = isVerified
        self.username = username
        self.password = password
        self.scheme = scheme
        self.url = url
    }
}
