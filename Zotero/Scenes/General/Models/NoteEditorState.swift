//
//  NoteEditorState.swift
//  Zotero
//
//  Created by Michal Rentka on 07.05.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

typealias NoteEditorKind = NoteEditorState.Kind

struct NoteEditorState: ViewModelState {
    enum Kind {
        case itemCreation(parentKey: String)
        case standaloneCreation(collection: Collection)
        case edit(key: String)
        case readOnly(key: String)

        var readOnly: Bool {
            switch self {
            case .readOnly:
                return true

            default:
                return false
            }
        }
    }

    struct Changes: OptionSet {
        typealias RawValue = UInt8

        let rawValue: UInt8

        static let tags = Changes(rawValue: 1 << 0)
        static let save = Changes(rawValue: 1 << 1)
        static let openItems = Changes(rawValue: 1 << 2)
    }

    struct TitleData {
        let type: String
        let title: String
    }

    enum Error: Swift.Error {
        case cantSaveReadonlyNote
    }

    let library: Library
    let title: TitleData?

    var kind: Kind
    var text: String
    var tags: [Tag]
    var changes: Changes
    var openItemsCount: Int

    init(kind: Kind, library: Library, title: TitleData?, text: String, tags: [Tag], openItemsCount: Int) {
        self.kind = kind
        self.text = text
        self.tags = tags
        self.library = library
        self.title = title
        changes = []
        self.openItemsCount = openItemsCount
    }

    mutating func cleanup() {
        changes = []
    }
}
