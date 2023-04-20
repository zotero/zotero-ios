//
//  FixSchemaIssueDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 20.04.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct FixSchemaIssueDbRequest: DbRequest {
    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        let items = database.objects(RItem.self).filter("rawType == %@ and any fields.key == %@", "dataset", "number")
        for item in items {
            guard let field = item.fields.filter("key == %@", "number").first else { continue }
            database.delete(field)
        }
    }
}
