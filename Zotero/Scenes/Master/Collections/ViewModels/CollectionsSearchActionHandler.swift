//
//  CollectionsSearchActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 05/08/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift

struct CollectionsSearchActionHandler: ViewModelActionHandler {
    typealias Action = CollectionsSearchAction
    typealias State = CollectionsSearchState

    func process(action: CollectionsSearchAction, in viewModel: ViewModel<CollectionsSearchActionHandler>) {
        switch action {
        case .search(let term):
            self.search(for: term, in: viewModel)
        }
    }

    private func search(for term: String, in viewModel: ViewModel<CollectionsSearchActionHandler>) {
        self.update(viewModel: viewModel) { state in
            if term.isEmpty {
                state.filtered = [:]
            } else {
                state.filtered = self.filter(collections: state.collections, with: term, rootCollections: viewModel.state.rootCollections, childCollections: viewModel.state.childCollections)
            }
        }
    }

    private func filter(collections: [CollectionIdentifier: Collection], with text: String, rootCollections: [CollectionIdentifier],
                        childCollections: [CollectionIdentifier: [CollectionIdentifier]]) -> [CollectionIdentifier: SearchableCollection] {
        var filtered: [CollectionIdentifier: SearchableCollection] = [:]
        self.add(collections: rootCollections, ifTheyContain: text, to: &filtered, childCollections: childCollections, allCollections: collections)
        return filtered
    }

    @discardableResult
    private func add(collections: [CollectionIdentifier], ifTheyContain text: String, to filtered: inout [CollectionIdentifier: SearchableCollection],
                     childCollections: [CollectionIdentifier: [CollectionIdentifier]], allCollections: [CollectionIdentifier: Collection]) -> Bool {
        var containsText = false

        for collectionId in collections {
            guard let collection = allCollections[collectionId] else { continue }

            if collection.name.localizedCaseInsensitiveContains(text) {
                containsText = true
                filtered[collectionId] = SearchableCollection(isActive: true, collection: collection)
            }

            if let children = childCollections[collectionId] {
                let childrenContainText = self.add(collections: children, ifTheyContain: text, to: &filtered, childCollections: childCollections, allCollections: allCollections)
                if !containsText && childrenContainText {
                    filtered[collectionId] = SearchableCollection(isActive: false, collection: collection)
                    containsText = true
                }
            }
        }

        return containsText
    }
}
