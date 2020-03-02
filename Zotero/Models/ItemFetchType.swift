//
//  ItemFetchType.swift
//  Zotero
//
//  Created by Michal Rentka on 02/03/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

/// Type of fetch request for items.
/// - all: Fetch all items.
/// - trash: Fetch trashed items.
/// - collection: Fetch items belonging to collection. First string is collection key, second collection name.
/// - search: Fetch items belonging to search. First string is search key, second search name.
enum ItemFetchType {
    case all, trash, publications
    case collection(String, String)
    case search(String, String)

    var collectionKey: String? {
        switch self {
        case .collection(let key, _):
            return key
        default:
            return nil
        }
    }

    var isTrash: Bool {
        switch self {
        case .trash:
            return true
        default:
            return false
        }
    }
}
