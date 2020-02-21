//
//  ItemsResultsCreator.swift
//  Zotero
//
//  Created by Michal Rentka on 21/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ItemResultsCreator {
    static func results(for type: ItemsState.ItemType, sortType: ItemsSortType,
                        libraryId: LibraryIdentifier, dbStorage: DbStorage) throws -> Results<RItem> {
        return try dbStorage.createCoordinator()
                            .perform(request: request(for: type, libraryId: libraryId))
                            .sorted(by: sortType.descriptors)
    }

    private static func request(for type: ItemsState.ItemType, libraryId: LibraryIdentifier) -> ReadItemsDbRequest {
        switch type {
        case .all:
            return ReadItemsDbRequest(libraryId: libraryId, collectionKey: nil, parentKey: "", trash: false)
        case .trash:
            return ReadItemsDbRequest(libraryId: libraryId, collectionKey: nil, parentKey: nil, trash: true)
        case .publications, .search:
            // TODO: - implement publications and search fetching
            return ReadItemsDbRequest(libraryId: .group(-1), collectionKey: nil, parentKey: nil, trash: true)
        case .collection(let key, _):
            return ReadItemsDbRequest(libraryId: libraryId, collectionKey: key, parentKey: "", trash: false)
        }
    }
}
