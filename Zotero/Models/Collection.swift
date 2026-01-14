//
//  Collection.swift
//  Zotero
//
//  Created by Michal Rentka on 19/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct Collection: Identifiable, Equatable, Hashable {
    let identifier: CollectionIdentifier
    let name: String
    var itemCount: Int
    let isAvailable: Bool

    var id: CollectionIdentifier {
        return identifier
    }

    var iconName: String {
        switch identifier {
        case .collection:
            return Asset.Images.Cells.collection.name

        case .search:
            return Asset.Images.Cells.document.name

        case .custom(let type):
            switch type {
            case .all, .publications:
                return Asset.Images.Cells.document.name

            case .unfiled:
                return Asset.Images.Cells.unfiled.name

            case .trash:
                return itemCount == 0 ? Asset.Images.Cells.trashEmpty.name : Asset.Images.Cells.trash.name
            }
        }
    }

    init(object: RCollection, itemCount: Int = 0, isAvailable: Bool = true) {
        identifier = .collection(object.key)
        name = object.name
        self.itemCount = itemCount
        self.isAvailable = isAvailable
    }

    init(object: RSearch) {
        identifier = .search(object.key)
        name = object.name
        itemCount = 0
        isAvailable = true
    }

    init(custom type: CollectionIdentifier.CustomType, itemCount: Int = 0) {
        self.itemCount = itemCount
        identifier = .custom(type)
        isAvailable = true

        switch type {
        case .all:
            name = L10n.Collections.allItems

        case .publications:
            name = L10n.Collections.myPublications

        case .trash:
            name = L10n.Collections.trash

        case .unfiled:
            name = L10n.Collections.unfiled
        }
    }

    private init(identifier: CollectionIdentifier, name: String, itemCount: Int, isAvailable: Bool) {
        self.identifier = identifier
        self.name = name
        self.itemCount = itemCount
        self.isAvailable = isAvailable
    }

    func isCustom(type: CollectionIdentifier.CustomType) -> Bool {
        switch identifier {
        case .custom(let customType):
            return type == customType

        case .collection, .search:
            return false
        }
    }

    var isCollection: Bool {
        switch identifier {
        case .collection:
            return true

        case .custom, .search:
            return false
        }
    }

    func copy(with itemCount: Int) -> Collection {
        return Collection(identifier: identifier, name: name, itemCount: itemCount, isAvailable: isAvailable)
    }
}
