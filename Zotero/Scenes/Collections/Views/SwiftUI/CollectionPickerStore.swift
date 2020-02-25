//
//  CollectionPickerStore.swift
//  Zotero
//
//  Created by Michal Rentka on 19/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import Foundation

import CocoaLumberjack
import RealmSwift
import RxSwift

class CollectionPickerStore: ObservableObject {
    enum Error: Swift.Error, Equatable {
        case dataLoading
    }

    struct State {
        let library: Library

        fileprivate(set) var collections: [Collection]
        fileprivate(set) var error: Error?
        fileprivate var token: NotificationToken?
        var selected: Set<String> = []
    }

    @Published var state: State

    init(library: Library, excludedKeys: Set<String>, dbStorage: DbStorage) {
        do {
            let collectionsRequest = ReadCollectionsDbRequest(libraryId: library.identifier, excludedKeys: excludedKeys)
            let results = try dbStorage.createCoordinator().perform(request: collectionsRequest)
            let collections = CollectionTreeBuilder.collections(from: results)
            self.state = State(library: library, collections: collections)

            self.state.token = results.observe({ changes in
                switch changes {
                case .update(let results, _, _, _):
                    self.state.collections = CollectionTreeBuilder.collections(from: results)
                case .initial: break
                case .error: break
                }
            })
        } catch let error {
            DDLogError("CollectionsStore: can't load collections: \(error)")
            self.state = State(library: library, collections: [], error: .dataLoading)
        }
    }
}
