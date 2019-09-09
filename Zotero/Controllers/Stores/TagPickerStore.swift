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
        var selectedTags: Set<Tag>
    }

    var state: State {
        willSet {
            self.objectWillChange.send()
        }
    }
    // SWIFTUI BUG: should be defined by default, but bugged in current version
    let objectWillChange: ObservableObjectPublisher
    let dbStorage: DbStorage

    init(libraryId: LibraryIdentifier, selectedTags: Set<Tag>, dbStorage: DbStorage) {
        self.state = State(libraryId: libraryId, tags: [], selectedTags: selectedTags)
        self.dbStorage = dbStorage
        self.objectWillChange = ObservableObjectPublisher()
    }

    func load() {
        // SWIFTUI BUG: - need to delay it a little because it's called on `onAppear` and it reloads the state immediately which causes a tableview reload crash, remove dispatch after when fixed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
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
}
