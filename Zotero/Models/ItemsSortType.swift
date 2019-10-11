//
//  ItemsSortType.swift
//  Zotero
//
//  Created by Michal Rentka on 09/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ItemsSortType {
    enum Field: CaseIterable, Identifiable {
        case creator, date, dateAdded, dateModified, itemType, publicationTitle, publisher, title, year

        var id: Int {
            return self.hashValue
        }

        var title: String {
            switch self {
            case .creator:
                return "Creator"
            case .date:
                return "Date"
            case .dateAdded:
                return "Date Added"
            case .dateModified:
                return "Date Modified"
            case .itemType:
                return "Item Type"
            case .publicationTitle:
                return "Publication Title"
            case .publisher:
                return "Publisher"
            case .title:
                return "Title"
            case .year:
                return "Year"
            }
        }
    }
    
    var field: Field
    var ascending: Bool
}

extension ItemsSortType: SortType {
    var descriptors: [SortDescriptor] {
        switch self.field {
        case .title:
            return [SortDescriptor(keyPath: "title", ascending: self.ascending)]
        case .creator:
            // TODO: - add appropriate descriptor
            return [SortDescriptor(keyPath: "title", ascending: self.ascending)]
        case .date:
            // TODO: - add appropriate descriptor
            return [SortDescriptor(keyPath: "title", ascending: self.ascending)]
        case .dateAdded:
            return [SortDescriptor(keyPath: "dateAdded", ascending: self.ascending)]
        case .dateModified:
            return [SortDescriptor(keyPath: "dateModified", ascending: self.ascending)]
        case .itemType:
            return [SortDescriptor(keyPath: "rawType", ascending: self.ascending)]
        case .publicationTitle:
            // TODO: - add appropriate descriptor
            return [SortDescriptor(keyPath: "title", ascending: self.ascending)]
        case .publisher:
            // TODO: - add appropriate descriptor
            return [SortDescriptor(keyPath: "title", ascending: self.ascending)]
        case .year:
            // TODO: - add appropriate descriptor
            return [SortDescriptor(keyPath: "title", ascending: self.ascending)]
        }
    }
}
