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
                state.collectionTree.cancelSearch()
            } else {
                state.collectionTree.search(for: term)
            }
        }
    }
}
