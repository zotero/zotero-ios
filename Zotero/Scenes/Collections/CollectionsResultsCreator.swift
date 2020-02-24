//
//  CollectionsResultsCreator.swift
//  Zotero
//
//  Created by Michal Rentka on 24/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

typealias CollectionsResults = ([Collection], Results<RCollection>, Results<RSearch>)

struct CollectionsResultsCreator {
    static func results(for libraryId: LibraryIdentifier, dbStorage: DbStorage) throws -> CollectionsResults {
        let collectionsRequest = ReadCollectionsDbRequest(libraryId: libraryId)
        let collections = try dbStorage.createCoordinator().perform(request: collectionsRequest)
        let searchesRequest = ReadSearchesDbRequest(libraryId: libraryId)
        let searches = try dbStorage.createCoordinator().perform(request: searchesRequest)

        var allCollections: [Collection] = [Collection(custom: .all),
                                            Collection(custom: .publications),
                                            Collection(custom: .trash)]
        allCollections.insert(contentsOf: CollectionTreeBuilder.collections(from: collections) +
                                          CollectionTreeBuilder.collections(from: searches),
                              at: 1)

        return (allCollections, collections, searches)
    }
}
