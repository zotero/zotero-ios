//
//  ItemsSortType.swift
//  Zotero
//
//  Created by Michal Rentka on 09/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ItemsSortType: Codable {
    enum Field: Int, CaseIterable, Identifiable, Codable {
        case creator, date, dateAdded, dateModified, itemType, publicationTitle, publisher, title, year

        var id: Int {
            return self.rawValue
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

        var defaultOrderAscending: Bool {
            switch self {
            case .creator:
                return true

            case .date:
                return false

            case .dateAdded:
                return false

            case .dateModified:
                return false

            case .itemType:
                return true

            case .publicationTitle:
                return true

            case .publisher:
                return true

            case .title:
                return true

            case .year:
                return false
            }
        }
    }
    
    var field: Field
    var ascending: Bool

    static var `default`: ItemsSortType {
        return ItemsSortType(field: .title, ascending: true)
    }
}

extension ItemsSortType: SortType {
    var descriptors: [RealmSwift.SortDescriptor] {
        switch self.field {
        case .title:
            return [SortDescriptor(keyPath: "sortTitle", ascending: self.ascending)]

        case .creator:
            return [SortDescriptor(keyPath: "hasCreatorSummary", ascending: false),
                    SortDescriptor(keyPath: "sortCreatorSummary", ascending: self.ascending),
                    SortDescriptor(keyPath: "sortTitle", ascending: true)]

        case .date:
            return [SortDescriptor(keyPath: "hasParsedDate", ascending: false),
                    SortDescriptor(keyPath: "parsedDate", ascending: self.ascending),
                    SortDescriptor(keyPath: "sortTitle", ascending: true)]

        case .dateAdded:
            return [SortDescriptor(keyPath: "dateAdded", ascending: self.ascending),
                    SortDescriptor(keyPath: "sortTitle", ascending: true)]

        case .dateModified:
            return [SortDescriptor(keyPath: "dateModified", ascending: self.ascending),
                    SortDescriptor(keyPath: "sortTitle", ascending: true)]

        case .itemType:
            return [SortDescriptor(keyPath: "localizedType", ascending: self.ascending),
                    SortDescriptor(keyPath: "sortTitle", ascending: true)]

        case .publicationTitle:
            return [SortDescriptor(keyPath: "hasPublicationTitle", ascending: false),
                    SortDescriptor(keyPath: "publicationTitle", ascending: self.ascending),
                    SortDescriptor(keyPath: "sortTitle", ascending: true)]

        case .publisher:
            return [SortDescriptor(keyPath: "hasPublisher", ascending: false),
                    SortDescriptor(keyPath: "publisher", ascending: self.ascending),
                    SortDescriptor(keyPath: "sortTitle", ascending: true)]

        case .year:
            return [SortDescriptor(keyPath: "hasParsedYear", ascending: false),
                    SortDescriptor(keyPath: "parsedYear", ascending: self.ascending),
                    SortDescriptor(keyPath: "sortTitle", ascending: true)]
        }
    }
}
