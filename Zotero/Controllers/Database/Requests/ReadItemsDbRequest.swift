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

        if Defaults.shared.showSubcollectionItems, case .collection(let key) = self.collectionId {
            // Filter results with subcollections
            let keys = self.selfAndSubcollectionKeys(for: key, in: database)
            results = database.objects(RItem.self).filter(.items(forCollections: keys, libraryId: self.libraryId))
        } else {
            // Filter results from given collection only
            results = database.objects(RItem.self).filter(.items(for: self.collectionId, libraryId: self.libraryId))
        }
        // Apply search
        if !self.searchTextComponents.isEmpty {
            results = results.filter(.itemSearch(for: self.searchTextComponents))
        }
        // Apply filters
        if !self.filters.isEmpty {
            for filter in self.filters {
                switch filter {
                case .downloadedFiles:
                    results = results.filter("fileDownloaded = true or any children.fileDownloaded = true")

                case .tags(let tags):
                    var predicates: [NSPredicate] = []
                    for tag in tags {
                        predicates.append(NSPredicate(format: "any tags.tag.name == %@ or any children.tags.tag.name == %@ or SUBQUERY(children, $item, any $item.children.tags.tag.name == %@).@count > 0", tag, tag, tag))
                    }
                    results = results.filter(NSCompoundPredicate(andPredicateWithSubpredicates: predicates))
                }
            }
        }
        // Sort if needed
        return self.sortType.flatMap({ results.sorted(by: $0.descriptors) }) ?? results
    }

    private func selfAndSubcollectionKeys(for key: String, in database: Realm) -> Set<String> {
        var keys: Set<String> = [key]
        let children = database.objects(RCollection.self).filter(.parentKey(key, in: self.libraryId))
        for child in children {
            keys.formUnion(self.selfAndSubcollectionKeys(for: child.key, in: database))
        }
        return keys
    }
}

struct ReadItemsWithKeysDbRequest: DbResponseRequest {
    typealias Response = Results<RItem>

    let keys: Set<String>
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Results<RItem> {
        return database.objects(RItem.self).filter(.keys(self.keys, in: self.libraryId))
    }
}
