//
//  NoteEditorState.swift
//  Zotero
//
//  Created by Michal Rentka on 07.05.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct NoteEditorState: ViewModelState {
    struct Changes: OptionSet {
        typealias RawValue = UInt8

        let rawValue: UInt8

        static let tags = Changes(rawValue: 1 << 0)
        static let save = Changes(rawValue: 1 << 1)
    }

    struct TitleData {
        let type: String
        let title: String
    }

    let title: TitleData?
    let libraryId: LibraryIdentifier
    let readOnly: Bool

    var text: String
    var tags: [Tag]
    var changes: Changes

    init(title: TitleData?, text: String, tags: [Tag], libraryId: LibraryIdentifier, readOnly: Bool) {
        self.text = text
        self.tags = tags
        self.title = title
        self.libraryId = libraryId
        self.readOnly = readOnly
        self.changes = []
    }

    mutating func cleanup() {
        self.changes = []
    }
}
