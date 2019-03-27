//
//  StoreItemDetailChangesDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 25/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjack
import RealmSwift

struct StoreItemDetailChangesDbRequest: DbRequest {
    var needsWrite: Bool {
        return true
    }

    let abstractKey: String

    let libraryId: LibraryIdentifier
    let itemKey: String
    let title: String
    let abstract: String?
    let fields: [ItemDetailStore.StoreState.Field]

    func process(in database: Realm) throws {
        let predicate = Predicates.keyInLibrary(key: self.itemKey, libraryId: self.libraryId)
        guard let item = database.objects(RItem.self).filter(predicate).first else { return }

        var fieldsDidChange = false
        item.fields.forEach { field in
            if field.key == self.abstractKey {
                if field.value != self.abstract {
                    field.value = self.abstract ?? ""
                    field.changed = true
                    fieldsDidChange = true
                }
            } else if RItem.titleKeys.contains(field.key) {
                if field.value != self.title {
                    field.value = self.title
                    field.changed = true
                    fieldsDidChange = true
                }
            } else if let localField = self.fields.first(where: { $0.name == field.key }) {
                if field.value != localField.value {
                    field.value = localField.value
                    field.changed = true
                    fieldsDidChange = true
                }
            }
        }

        if fieldsDidChange {
            item.changedFields.insert(.fields)
        }
    }
}
