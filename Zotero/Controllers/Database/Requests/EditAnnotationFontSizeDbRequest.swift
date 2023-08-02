//
//  EditAnnotationFontSizeDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 01.08.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct EditAnnotationFontSizeDbRequest: DbRequest {
    let key: String
    let libraryId: LibraryIdentifier
    let size: UInt

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        guard let item = database.objects(RItem.self).filter(.key(self.key, in: self.libraryId)).first else { return }

        let field: RItemField
        if let _field = item.fields.filter(.key(FieldKeys.Item.Annotation.Position.fontSize)).first {
            field = _field
        } else {
            field = RItemField()
            field.key = FieldKeys.Item.Annotation.Position.fontSize
            field.baseKey = FieldKeys.Item.Annotation.position
            item.fields.append(field)
        }

        field.value = "\(self.size)"
    }
}
