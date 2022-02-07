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
//    var level: Int
//    let parentKey: String?
//    var hasChildren: Bool
//    var collapsed: Bool
//    var visible: Bool
    var itemCount: Int

    var id: CollectionIdentifier {
        return self.identifier
    }

    func iconName(hasChildren: Bool) -> String {
        switch self.identifier {
        case .collection:
            if hasChildren {
                return Asset.Images.Cells.collectionChildren.name
            } else {
                return Asset.Images.Cells.collection.name
            }
        case .search:
            return Asset.Images.Cells.document.name
        case .custom(let type):
            switch type {
            case .all, .publications:
                return Asset.Images.Cells.document.name
            case .trash:
                return Asset.Images.Cells.trash.name
            }
        }
    }

    init(object: RCollection, itemCount: Int) {
        self.identifier = .collection(object.key)
        self.name = object.name
        self.itemCount = itemCount
    }

    init(object: RSearch) {
        self.identifier = .search(object.key)
        self.name = object.name
        self.itemCount = 0
    }

    init(custom type: CollectionIdentifier.CustomType, itemCount: Int = 0) {
        self.itemCount = itemCount
        self.identifier = .custom(type)
        switch type {
        case .all:
            self.name = L10n.Collections.allItems
        case .publications:
            self.name = L10n.Collections.myPublications
        case .trash:
            self.name = L10n.Collections.trash
        }
    }

    func isCustom(type: CollectionIdentifier.CustomType) -> Bool {
        switch self.identifier {
        case .custom(let customType):
            return type == customType
        case .collection, .search:
            return false
        }
    }
}
