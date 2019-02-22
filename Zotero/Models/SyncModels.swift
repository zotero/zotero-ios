//
//  SyncModels.swift
//  Zotero
//
//  Created by Michal Rentka on 06/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

public enum SyncLibraryType: Equatable {
    case user(Int)
    case group(Int)

    var apiPath: String {
        switch self {
        case .group(let identifier):
            return "groups/\(identifier)"
        case .user(let identifier):
            return "users/\(identifier)"
        }
    }

    var fileComponent: String {
        switch self {
        case .group(let identifier):
            return "group\(identifier)"
        case .user(let identifier):
            return "user\(identifier)"
        }
    }

    var libraryId: Int {
        switch self {
        case .group(let identifier):
            return identifier
        case .user:
            return RLibrary.myLibraryId
        }
    }
}

public enum SyncObjectType: Equatable {
    case group, collection, search, item, trash

    var apiPath: String {
        switch self {
        case .group:
            return "groups"
        case .collection:
            return "collections"
        case .search:
            return "searches"
        case .item:
            return "items"
        case .trash:
            return "items/trash"
        }
    }

    var fileComponent: String {
        switch self {
        case .group:
            return "groups"
        case .collection:
            return "collections"
        case .search:
            return "searches"
        case .item:
            return "items"
        case .trash:
            return "trash"
        }
    }
}
