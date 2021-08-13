//
//  StoreStyleDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 04.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct StoreStyleDbRequest: DbRequest {
    let style: Style
    let dependency: Style?

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws {
        let (rStyle, _) = self.style(for: self.style.identifier, database: database)
        rStyle.href = self.style.href.absoluteString
        rStyle.title = self.style.title
        rStyle.updated = self.style.updated
        rStyle.filename = self.style.filename
        rStyle.installed = true
        rStyle.supportsBibliography = self.style.supportsBibliography
        rStyle.defaultLocale = self.style.defaultLocale ?? ""

        if let dependency = self.dependency {
            let (rDependency, existed) = self.style(for: dependency.identifier, database: database)
            rDependency.updated = dependency.updated
            rDependency.filename = dependency.filename
            rDependency.href = dependency.href.absoluteString
            rDependency.title = dependency.title
            rDependency.supportsBibliography = dependency.supportsBibliography
            rDependency.defaultLocale = dependency.defaultLocale ?? ""
            if !existed {
                rDependency.installed = false
            }

            rStyle.supportsBibliography = dependency.supportsBibliography
            rStyle.dependency = rDependency
        }
    }

    private func style(for identifier: String, database: Realm) -> (RStyle, Bool) {
        if let existing = database.object(ofType: RStyle.self, forPrimaryKey: identifier) {
            return (existing, true)
        } else {
            let rStyle = RStyle()
            rStyle.identifier = identifier
            database.add(rStyle)
            return (rStyle, false)
        }
    }
}

