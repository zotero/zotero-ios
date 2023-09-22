//
//  ReadItemsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 11/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadItemsDbRequest: DbResponseRequest {
    typealias Response = Results<RItem>

    let collectionId: CollectionIdentifier
    let libraryId: LibraryIdentifier
    let filters: [ItemsFilter]
    let sortType: ItemsSortType?
    let searchTextComponents: [String]

    var needsWrite: Bool { return false }

    init(collectionId: CollectionIdentifier, libraryId: LibraryIdentifier, filters: [ItemsFilter] = [], sortType: ItemsSortType? = nil, searchTextComponents: [String] = []) {
        self.collectionId = collectionId
        self.libraryId = libraryId
        self.filters = filters
        self.sortType = sortType
        self.searchTextComponents = searchTextComponents
    }

    func process(in database: Realm) throws -> Results<RItem> {
        var results: Results<RItem>

        if Defaults.shared.showSubcollectionItems, case .collection(let key) = collectionId {
            // Filter results with subcollections
            let keys = database.selfAndSubcollectionKeys(for: key, libraryId: libraryId)
            results = database.objects(RItem.self).filter(.items(forCollections: keys, libraryId: libraryId))
        } else {
            // Filter results from given collection only
            results = database.objects(RItem.self).filter(.items(for: collectionId, libraryId: libraryId))
        }
        // Apply search
        if !searchTextComponents.isEmpty {
            results = results.filter(.itemSearch(for: searchTextComponents))
        }
        // Apply filters
        for filter in filters {
            switch filter {
            case .downloadedFiles:
                results = results.filter("fileDownloaded = true or any children.fileDownloaded = true")

            case .tags(let tags):
                var predicates: [NSPredicate] = []
                for tag in tags {
                    predicates.append(NSPredicate(
                        format: "any tags.tag.name == %@ or any children.tags.tag.name == %@ or SUBQUERY(children, $item, any $item.children.tags.tag.name == %@).@count > 0", tag, tag, tag)
                    )
                }
                results = results.filter(NSCompoundPredicate(andPredicateWithSubpredicates: predicates))
            }
        }
        // Sort if needed
        return sortType.flatMap({ results.sorted(by: $0.descriptors) }) ?? results
    }
}

struct ReadItemsWithKeysDbRequest: DbResponseRequest {
    typealias Response = Results<RItem>

    let keys: Set<String>
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Results<RItem> {
        return database.objects(RItem.self).filter(.keys(keys, in: libraryId))
    }
}

struct ReadLibraryItemsDbRequest: DbResponseRequest {
    typealias Response = Results<RItem>

    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Results<RItem> {
        return database.objects(RItem.self).filter(.items(for: libraryId))
    }
}

struct ReadItemsWithKeysFromMultipleLibrariesDbRequest: DbResponseRequest {
    typealias Response = Results<RItem>

    let keysByLibraryIdentifier: [LibraryIdentifier: Set<String>]

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Results<RItem> {
        database.objects(RItem.self).filter(.keysByLibraryIdentifier(keysByLibraryIdentifier))
    }
}
