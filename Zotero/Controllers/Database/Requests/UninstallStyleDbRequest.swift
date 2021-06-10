//
//  UninstallStyleDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 04.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct UninstallStyleDbRequest: DbResponseRequest {
    typealias Response = [String]

    let identifier: String

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws -> [String] {
        guard let style = database.object(ofType: RStyle.self, forPrimaryKey: self.identifier) else { return [] }

        // If some styles are dependent on this one, just flip the `installed` flag.
        if !style.dependent.isEmpty {
            style.installed = false
            return []
        }

        var toRemove: [String] = [style.filename]

        if let dependency = style.dependency {
            // If the dependency is not installed and it doesn't have any other depending styles, just delete it.
            if !dependency.installed && dependency.dependent.count == 1 {
                toRemove.append(dependency.filename)
                database.delete(dependency)
            }
        }

        database.delete(style)

        return toRemove
    }
}
