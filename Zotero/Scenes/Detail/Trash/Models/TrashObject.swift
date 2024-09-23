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
    struct ItemSortData {
        let title: String
        let type: String
        let creatorSummary: String
        let publisher: String?
        let publicationTitle: String?
        let year: Int?
        let date: Date?
        let dateAdded: Date
    }

    struct ItemCellData {
        let localizedTypeName: String
        let typeIconName: String
        let subtitle: String
        let accessory: ItemCellModel.Accessory?
        let tagColors: [UIColor]
        let tagEmojis: [String]
        let hasNote: Bool
    }

    enum Kind {
        case collection
        case item(cellData: ItemCellData, sortData: ItemSortData, accessory: ItemAccessory?)
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

        case .item(_, let sortData, _):
            return sortData.title
        }
    }

    var sortType: String? {
        switch type {
        case .item(_, let sortData, _):
            return sortData.type

        case .collection:
            return nil
        }
    }

    var creatorSummary: String? {
        switch type {
        case .item(_, let sortData, _):
            return sortData.creatorSummary

        case .collection:
            return nil
        }
    }

    var publisher: String? {
        switch type {
        case .item(_, let sortData, _):
            return sortData.publisher

        case .collection:
            return nil
        }
    }

    var publicationTitle: String? {
        switch type {
        case .item(_, let sortData, _):
            return sortData.publicationTitle

        case .collection:
            return nil
        }
    }

    var year: Int? {
        switch type {
        case .item(_, let sortData, _):
            return sortData.year

        case .collection:
            return nil
        }
    }

    var date: Date? {
        switch type {
        case .item(_, let sortData, _):
            return sortData.date

        case .collection:
            return nil
        }
    }

    var dateAdded: Date? {
        switch type {
        case .item(_, let sortData, _):
            return sortData.dateAdded

        case .collection:
            return nil
        }
    }

    var itemAccessory: ItemAccessory? {
        switch type {
        case .item(_, _, let accessory):
            return accessory

        case .collection:
            return nil
        }
    }
}
