//
//  Note.swift
//  Zotero
//
//  Created by Michal Rentka on 21/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift

struct Note: Identifiable, Equatable {
    let key: String
    var title: String
    var text: String

    var id: String { return self.key }

    init(key: String, text: String) {
        self.key = key
        self.title = text.notePreview ?? text
        self.text = text
    }

    init?(item: RItem) {
        guard item.rawType == ItemTypes.note else {
            DDLogError("Trying to create Note from RItem which is not a note!")
            return nil
        }

        self.key = item.key
        self.title = item.displayTitle
        self.text = item.fields.filter(.key(ItemFieldKeys.note)).first?.value ?? ""
    }
}
