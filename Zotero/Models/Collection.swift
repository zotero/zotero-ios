//
//  Collection.swift
//  Zotero
//
//  Created by Michal Rentka on 19/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct Collection: Identifiable, Equatable {
    
    enum CollectionType: Equatable {
        case collection
        case search
        case custom(CustomType)
        
        var isCustom: Bool {
            switch self {
            case .custom: return true
            default: return false
            }
        }
    }

    enum CustomType: Equatable {
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
    
    var iconName: String {
        switch self.type {
        case .collection:
            return "icon_cell_collection"
        case .search:
            return "icon_cell_document"
        case .custom(let type):
            switch type {
            case .all, .publications:
                return "icon_cell_document"
            case .trash:
                return "icon_cell_trash"
            }
        }
    }

    init(object: RCollection, level: Int) {
        self.type = .collection
        self.key = object.key
        self.name = object.name
        self.level = level
    }

    init(object: RSearch) {
        self.type = .search
        self.key = object.key
        self.name = object.name
        self.level = 0
    }

    init(custom type: CustomType) {
        self.type = .custom(type)
        self.key = ""
        self.level = 0
        switch type {
        case .all:
            self.name = "All Items"
        case .publications:
            self.name = "My Publications"
        case .trash:
            self.name = "Trash"
        }
    }
}
