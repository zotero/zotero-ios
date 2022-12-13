//
//  FixNotesWithEmptyTitlesDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 13.12.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct FixNotesWithEmptyTitlesDbRequest: DbRequest {
    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        let items = database.objects(RItem.self).filter("rawType == %@ AND (baseTitle == \"\" OR displayTitle == \"\")", ItemTypes.note)
        for item in items {
            guard let field = item.fields.filter(.key(FieldKeys.Item.note)).first, !field.value.isEmpty, let title = NotePreviewGenerator.preview(from: field.value), !title.isEmpty else { continue }
            item.set(title: title)
        }
    }
}
