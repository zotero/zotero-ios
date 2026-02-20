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
    struct Resource {
        let identifier: String
        let data: [String: Any]
    }

    struct CreatedImage {
        let nodeId: String
        let key: String
    }

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
        static let shouldSave = Changes(rawValue: 1 << 1)
        static let openItems = Changes(rawValue: 1 << 2)
        static let kind = Changes(rawValue: 1 << 3)
        static let title = Changes(rawValue: 1 << 4)
        static let saved = Changes(rawValue: 1 << 5)
        static let closing = Changes(rawValue: 1 << 6)
    }

    struct TitleData {
        let type: String
        let title: String
    }

    enum Error: Swift.Error {
        case cantCreateData
        case cantSaveReadonlyNote
    }

    let library: Library
    let parentTitleData: TitleData?

    var kind: Kind
    var text: String
    var tags: [Tag]
    var downloadedResource: Resource?
    var createdImages: [CreatedImage]
    var changes: Changes
    var openItemsCount: Int
    var title: String?
    var isClosing: Bool
    var error: Swift.Error?

    init(kind: Kind, library: Library, parentTitleData: TitleData?, text: String, tags: [Tag], openItemsCount: Int, title: String?) {
        self.kind = kind
        self.text = text
        self.tags = tags
        self.library = library
        self.parentTitleData = parentTitleData
        self.openItemsCount = openItemsCount
        self.title = title
        isClosing = false
        changes = []
        createdImages = []
    }

    mutating func cleanup() {
        downloadedResource = nil
        changes = []
        createdImages = []
        error = nil
    }
}
