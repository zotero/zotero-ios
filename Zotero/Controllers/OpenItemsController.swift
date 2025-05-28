//
//  OpenItemsController.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 20/9/23.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

typealias OpenItem = OpenItemsController.Item
typealias ItemPresentation = OpenItemsController.Presentation

protocol OpenItemsPresenter: AnyObject {
    func showItem(with presentation: ItemPresentation?)
}

final class OpenItemsController {
    // MARK: Types
    struct Item: Hashable, Equatable, Codable {
        enum Kind: Hashable, Equatable, Codable {
            case pdf(libraryId: LibraryIdentifier, key: String)
            case html(libraryId: LibraryIdentifier, key: String)
            case epub(libraryId: LibraryIdentifier, key: String)
            case note(libraryId: LibraryIdentifier, key: String)

            // MARK: Properties
            var libraryId: LibraryIdentifier {
                switch self {
                case .pdf(let libraryId, _), .note(let libraryId, _), .html(let libraryId, _), .epub(let libraryId, _):
                    return libraryId
                }
            }

            var key: String {
                switch self {
                case .pdf(_, let key), .note(_, let key), .html(_, let key), .epub(_, let key):
                    return key
                }
            }

            var icon: UIImage {
                switch self {
                case .pdf:
                    return Asset.Images.ItemTypes.pdf.image

                case .html:
                    return Asset.Images.ItemTypes.webPageSnapshot.image

                case .epub:
                    return Asset.Images.ItemTypes.document.image

                case .note:
                    return Asset.Images.ItemTypes.note.image
                }
            }

            // MARK: Codable
            enum CodingKeys: CodingKey {
                case pdfKind
                case noteKind
                case epubKind
                case htmlKind
                case libraryId
                case key
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                switch self {
                case .pdf:
                    try container.encode(true, forKey: .pdfKind)

                case .epub:
                    try container.encode(true, forKey: .epubKind)

                case .html:
                    try container.encode(true, forKey: .htmlKind)

                case .note:
                    try container.encode(true, forKey: .noteKind)
                }

                try container.encode(libraryId, forKey: .libraryId)
                try container.encode(key, forKey: .key)
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                let libraryId = try container.decode(LibraryIdentifier.self, forKey: .libraryId)
                let key = try container.decode(String.self, forKey: .key)
                if (try? container.decode(Bool.self, forKey: .pdfKind)) == true {
                    self = .pdf(libraryId: libraryId, key: key)
                } else if (try? container.decode(Bool.self, forKey: .noteKind)) == true {
                    self = .note(libraryId: libraryId, key: key)
                } else if (try? container.decode(Bool.self, forKey: .epubKind)) == true {
                    self = .epub(libraryId: libraryId, key: key)
                } else if (try? container.decode(Bool.self, forKey: .htmlKind)) == true {
                    self = .html(libraryId: libraryId, key: key)
                } else {
                    throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [CodingKeys.pdfKind, CodingKeys.noteKind], debugDescription: "Item kind key not found"))
                }
            }
        }

        let kind: Kind
        var userIndex: Int
        var lastOpened: Date

        init(kind: Kind, userIndex: Int, lastOpened: Date = .now) {
            self.kind = kind
            self.userIndex = userIndex
            self.lastOpened = lastOpened
        }
    }

    enum Presentation {
        case pdf(library: Library, key: String, parentKey: String?, url: URL)
        case html(library: Library, key: String, parentKey: String?, url: URL)
        case epub(library: Library, key: String, parentKey: String?, url: URL)
        case note(library: Library, key: String, text: String, tags: [Tag], parentTitleData: NoteEditorState.TitleData?, title: String)
    }
}
