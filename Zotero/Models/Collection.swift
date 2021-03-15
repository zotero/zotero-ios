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

    enum CollectionType: Equatable, Hashable {
        case collection
        case search
        case custom(CustomType)
        
        var isCustom: Bool {
            switch self {
            case .custom: return true
            default: return false
            }
        }

        var isCollection: Bool {
            switch self {
            case .collection: return true
            default: return false
            }
        }
    }

    enum CustomType: Equatable, Hashable {
        case all, trash, publications
    }
    
    var id: String {
        switch self.type {
        case .custom(let type):
            switch type {
            case .all: return "all"
            case .publications: return "publications"
            case .trash: return "trash"
            }
        case .collection, .search:
            return self.key
        }
    }

    let type: CollectionType
    let key: String
    let name: String
    let level: Int
    let parentKey: String?
    let hasChildren: Bool
    var collapsed: Bool
    var visible: Bool
    var itemCount: Int

    var iconName: String {
        switch self.type {
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
        self.type = .collection
        self.key = object.key
        self.name = object.name
        self.level = level
        self.hasChildren = hasChildren
        self.collapsed = object.collapsed
        self.visible = visible
        self.itemCount = itemCount
        self.parentKey = parentKey
    }

    init(object: RSearch) {
        self.type = .search
        self.key = object.key
        self.name = object.name
        self.level = 0
        self.itemCount = 0
        self.hasChildren = false
        self.collapsed = false
        self.visible = true
        self.parentKey = nil
    }

    init(custom type: CustomType, itemCount: Int = 0) {
        self.itemCount = itemCount
        self.type = .custom(type)
        self.key = ""
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

    func isCustom(type: CustomType) -> Bool {
        switch self.type {
        case .custom(let customType):
            return type == customType
        case .collection, .search:
            return false
        }
    }
}
