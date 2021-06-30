//
//  Style.swift
//  Zotero
//
//  Created by Michal Rentka on 03.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift

struct Style: Identifiable {
    let identifier: String
    let title: String
    let updated: Date
    let href: URL
    let filename: String

    var id: String {
        return self.identifier
    }

    init(identifier: String, title: String, updated: Date, href: URL, filename: String) {
        self.identifier = identifier
        self.title = title
        self.updated = updated
        self.href = href
        self.filename = filename
    }

    init?(rStyle: RStyle) {
        guard let href = URL(string: rStyle.href) else {
            DDLogError("Style: RStyle has wrong href - \"\(rStyle.href)\"")
            return nil
        }
        self.identifier = rStyle.identifier
        self.title = rStyle.title
        self.updated = rStyle.updated
        self.href = href
        self.filename = rStyle.filename
    }
}
