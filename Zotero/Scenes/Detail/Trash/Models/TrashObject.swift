//
//  File.swift
//  Zotero
//
//  Created by Michal Rentka on 18.07.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

struct TrashKey: Hashable {
    enum Kind: Hashable {
        case collection
        case item
    }

    let type: Kind
    let key: String
}

struct TrashObject {
    struct Item {
        let sortTitle: String
        let type: String
        let localizedTypeName: String
        let typeIconName: String
        let creatorSummary: String
        let publisher: String?
        let publicationTitle: String?
        let year: Int?
        let date: Date?
        let dateAdded: Date
        let tagNames: Set<String>
        let tagColors: [UIColor]
        let tagEmojis: [String]
        let hasNote: Bool
        let itemAccessory: ItemAccessory?
        let isMainAttachmentDownloaded: Bool
        let searchStrings: Set<String>

        func copy(itemAccessory: ItemAccessory?) -> Item {
            return .init(
                sortTitle: sortTitle,
                type: type,
                localizedTypeName: localizedTypeName,
                typeIconName: typeIconName,
                creatorSummary: creatorSummary,
                publisher: publisher,
                publicationTitle: publicationTitle,
                year: year,
                date: date,
                dateAdded: dateAdded,
                tagNames: tagNames,
                tagColors: tagColors,
                tagEmojis: tagEmojis,
                hasNote: hasNote,
                itemAccessory: itemAccessory,
                isMainAttachmentDownloaded: isMainAttachmentDownloaded,
                searchStrings: searchStrings
            )
        }
    }

    enum Kind {
        case collection
        case item(item: Item)
    }

    let type: Kind
    let key: String
    let libraryId: LibraryIdentifier
    let title: NSAttributedString
    let dateModified: Date

    var trashKey: TrashKey {
        let keyType: TrashKey.Kind
        switch type {
        case .collection:
            keyType = .collection

        case .item:
            keyType = .item
        }
        return TrashKey(type: keyType, key: key)
    }

    var sortTitle: String {
        switch type {
        case .collection:
            return title.string

        case .item(let item):
            return item.sortTitle
        }
    }

    var sortType: String? {
        switch type {
        case .item(let item):
            return item.type

        case .collection:
            return nil
        }
    }

    var creatorSummary: String? {
        switch type {
        case .item(let item):
            return item.creatorSummary

        case .collection:
            return nil
        }
    }

    var publisher: String? {
        switch type {
        case .item(let item):
            return item.publisher

        case .collection:
            return nil
        }
    }

    var publicationTitle: String? {
        switch type {
        case .item(let item):
            return item.publicationTitle

        case .collection:
            return nil
        }
    }

    var year: Int? {
        switch type {
        case .item(let item):
            return item.year

        case .collection:
            return nil
        }
    }

    var date: Date? {
        switch type {
        case .item(let item):
            return item.date

        case .collection:
            return nil
        }
    }

    var dateAdded: Date? {
        switch type {
        case .item(let item):
            return item.dateAdded

        case .collection:
            return dateModified
        }
    }

    var itemAccessory: ItemAccessory? {
        switch type {
        case .item(let item):
            return item.itemAccessory

        case .collection:
            return nil
        }
    }

    func updated(itemAccessory: ItemAccessory) -> TrashObject? {
        switch type {
        case .collection:
            return nil

        case .item(let item):
            return TrashObject(
                type: .item(item: item.copy(itemAccessory: itemAccessory)),
                key: key,
                libraryId: libraryId,
                title: title,
                dateModified: dateModified
            )
        }
    }
}
