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
                state.filtered = []
            } else {
                state.filtered = self.filter(collections: state.collections, with: term)
            }
        }
    }

    private func filter(collections: [SearchableCollection], with text: String) -> [SearchableCollection] {
        var filtered: [SearchableCollection] = []

        // Go through all collections, find results and insert their parents.
//        for (i, searchable) in collections.enumerated() {
//            guard searchable.collection.name.localizedCaseInsensitiveContains(text) else { continue }
//
//            // Check whether we need to look for parents of this collection. We need to look for parents when the level > 0
//            // (otherwise there are no parents) and previously inserted collection doesn't have the same parent as this one
//            // (otherwise we already have all parents from previous collection).
//            let shouldLookForParents = searchable.collection.level > 0 && filtered.last?.collection.parentKey != searchable.collection.parentKey
//
//            // Collection contains text, append.
//            filtered.append(searchable.isActive(true))
//
//            guard shouldLookForParents else { continue }
//
//            // Track back to search for all parents
//            let insertionIndex = filtered.count - 1
//            var lastLevel = searchable.collection.level
//
//            for j in (0..<i).reversed() {
//                let parent = collections[j]
//
//                // If level changed, we found a new parent
//                guard parent.collection.level < lastLevel else { continue }
//
//                // Parent is already in filtered array, stop searching for parents
//                if filtered.reversed().firstIndex(where: { $0.collection == parent.collection }) != nil {
//                    break
//                }
//
//                filtered.insert(parent.isActive(false), at: insertionIndex)
//
//                // If this parent is already on root level, stop searching for parents
//                if parent.collection.level == 0 {
//                    break
//                }
//
//                lastLevel = parent.collection.level
//            }
//        }

        return filtered
    }
}
