//
//  Note.swift
//  Zotero
//
//  Created by Michal Rentka on 21/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift

struct Note: Identifiable, Equatable, Hashable {
    let key: String
    var title: String
    var text: String
    var tags: [Tag]

    var id: String { return self.key }

    init(key: String, text: String, tags: [Tag]) {
        self.key = key
        self.title = NotePreviewGenerator.preview(from: text) ?? text
        self.text = text
        self.tags = tags
    }

    init?(item: RItem) {
        guard item.rawType == ItemTypes.note else {
            DDLogError("Trying to create Note from RItem which is not a note!")
            return nil
        }

        self.key = item.key
        self.title = item.displayTitle
        self.text = item.fields.filter(.key(FieldKeys.Item.note)).first?.value ?? ""
        self.tags = Array(item.tags.map({ Tag(tag: $0) }))
    }
}
