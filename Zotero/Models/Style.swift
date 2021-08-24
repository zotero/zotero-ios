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
    let supportsBibliography: Bool
    let isNoteStyle: Bool
    let dependencyId: String?
    let defaultLocale: String?

    var id: String {
        return self.identifier
    }

    init(identifier: String, dependencyId: String?, title: String, updated: Date, href: URL, filename: String, supportsBibliography: Bool, isNoteStyle: Bool, defaultLocale: String?) {
        self.identifier = identifier
        self.title = title
        self.updated = updated
        self.href = href
        self.filename = filename
        self.supportsBibliography = supportsBibliography
        self.isNoteStyle = isNoteStyle
        self.dependencyId = dependencyId
        self.defaultLocale = defaultLocale
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
        self.supportsBibliography = rStyle.supportsBibliography
        self.isNoteStyle = rStyle.isNoteStyle
        self.dependencyId = rStyle.dependency?.identifier
        self.defaultLocale = rStyle.defaultLocale.isEmpty ? nil : rStyle.defaultLocale
    }
}
