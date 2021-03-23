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
    var level: Int
    let parentKey: String?
    var hasChildren: Bool
    var collapsed: Bool
    var visible: Bool
    var itemCount: Int

    var id: CollectionIdentifier {
        return self.identifier
    }

    var iconName: String {
        switch self.identifier {
        case .collection:
            return Asset.Images.Cells.collection.name
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

    init(object: RCollection, level: Int, visible: Bool, hasChildren: Bool, parentKey: String?, itemCount: Int) {
        self.identifier = .collection(object.key)
        self.name = object.name
        self.level = level
        self.hasChildren = hasChildren
        self.collapsed = object.collapsed
        self.visible = visible
        self.itemCount = itemCount
        self.parentKey = parentKey
    }

    init(object: RSearch) {
        self.identifier = .search(object.key)
        self.name = object.name
        self.level = 0
        self.itemCount = 0
        self.hasChildren = false
        self.collapsed = false
        self.visible = true
        self.parentKey = nil
    }

    init(custom type: CollectionIdentifier.CustomType, itemCount: Int = 0) {
        self.itemCount = itemCount
        self.identifier = .custom(type)
        self.level = 0
        self.parentKey = nil
        self.hasChildren = false
        self.collapsed = false
        self.visible = true
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
