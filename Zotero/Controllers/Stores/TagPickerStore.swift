//
//  TagPickerStore.swift
//  Zotero
//
//  Created by Michal Rentka on 09/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import Foundation

import CocoaLumberjack

class TagPickerStore: ObservableObject {
    enum Error: Swift.Error {
        case loadingFailed
    }

    struct State {
        let libraryId: LibraryIdentifier
        var tags: [Tag]
        var error: Error?
        var selectedTags: Set<String>
    }

    @Published var state: State
    private let dbStorage: DbStorage

    init(libraryId: LibraryIdentifier, selectedTags: Set<String>, dbStorage: DbStorage) {
        self.state = State(libraryId: libraryId, tags: [], selectedTags: selectedTags)
        self.dbStorage = dbStorage
    }

    func load() {
        do {
            let request = ReadTagsDbRequest(libraryId: self.state.libraryId)
            self.state.tags = try self.dbStorage.createCoordinator().perform(request: request)
            NSLog("TAGS: \(self.state.tags)")
        } catch let error {
            DDLogError("TagPickerStore: can't load tag: \(error)")
            self.state.error = .loadingFailed
        }
    }
}
