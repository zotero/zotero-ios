//
//  SyncObject.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum SyncObject: CaseIterable, Equatable {
    case group, collection, search, item, trash, tag
}

extension SyncObject {
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
        case .tag:
            return "tags"
        }
    }
}
