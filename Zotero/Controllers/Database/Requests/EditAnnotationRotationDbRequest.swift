//
//  EditAnnotationRotationDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 28.07.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct EditAnnotationRotationDbRequest: DbRequest {
    let key: String
    let libraryId: LibraryIdentifier
    let rotation: UInt

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        guard let item = database.objects(RItem.self).uniqueObject(key: key, libraryId: libraryId) else { return }

        let field: RItemField
        if let _field = item.fields.filter(.key(FieldKeys.Item.Annotation.Position.rotation)).first {
            field = _field
        } else {
            field = RItemField()
            field.key = FieldKeys.Item.Annotation.Position.rotation
            field.baseKey = FieldKeys.Item.Annotation.position
            item.fields.append(field)
        }

        field.value = "\(self.rotation)"
        item.changeType = .user
        item.changes.append(RObjectChange.create(changes: RItemChanges.fields))
    }
}
