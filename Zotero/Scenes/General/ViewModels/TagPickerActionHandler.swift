//
//  TagPickerActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 09/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import Foundation

import CocoaLumberjackSwift
import RealmSwift

struct TagPickerActionHandler: ViewModelActionHandler {
    typealias Action = TagPickerAction
    typealias State = TagPickerState

    private unowned let dbStorage: DbStorage

    init(dbStorage: DbStorage) {
        self.dbStorage = dbStorage
    }

    func process(action: TagPickerAction, in viewModel: ViewModel<TagPickerActionHandler>) {
        switch action {
        case .select(let name):
            self.update(viewModel: viewModel) { state in
                state.selectedTags.insert(name)
                state.changes = .selection
            }

        case .deselect(let name):
            self.update(viewModel: viewModel) { state in
                state.selectedTags.remove(name)
                state.changes = .selection
            }

        case .load:
            self.load(for: viewModel.state.libraryId, clearSelection: false, in: viewModel)

        case .search(let term):
            self.search(with: term, in: viewModel)

        case .add(let name):
            self.add(name: name, in: viewModel)

        case .changeLibrary(let libraryId):
            self.load(for: libraryId, clearSelection: true, in: viewModel)
        }
    }

    private func add(name: String, in viewModel: ViewModel<TagPickerActionHandler>) {
        guard let snapshot = viewModel.state.snapshot else { return }
        self.update(viewModel: viewModel) { state in
            let tag = Tag(name: name, color: "")
            state.tags = snapshot

            let index = state.tags.index(of: tag, sortedBy: { $0.name.caseInsensitiveCompare($1.name) == .orderedAscending })
            state.tags.insert(tag, at: index)
            state.selectedTags.insert(name)

            state.snapshot = nil
            state.searchTerm = ""
            state.addedTagName = name
            state.showAddTagButton = false
            state.changes = [.tags, .selection]
        }
    }

    private func search(with term: String, in viewModel: ViewModel<TagPickerActionHandler>) {
        if !term.isEmpty {
            self.update(viewModel: viewModel) { state in
                if state.snapshot == nil {
                    state.snapshot = state.tags
                }
                state.searchTerm = term
                state.tags = (state.snapshot ?? state.tags).filter({ $0.name.localizedCaseInsensitiveContains(term) })
                state.changes = .tags
                state.showAddTagButton = state.tags.isEmpty || state.tags.first(where: { $0.name == term }) == nil
            }
        } else {
            guard let snapshot = viewModel.state.snapshot else { return }
            self.update(viewModel: viewModel) { state in
                state.tags = snapshot
                state.snapshot = nil
                state.searchTerm = ""
                state.changes = .tags
                state.showAddTagButton = false
            }
        }
    }

    private func load(for libraryId: LibraryIdentifier, clearSelection: Bool, in viewModel: ViewModel<TagPickerActionHandler>) {
        do {
            let request = ReadTagsDbRequest(libraryId: libraryId)
            let results = try self.dbStorage.perform(request: request, on: .main)
            var tags = Array(results.map(Tag.init))
            var token: NotificationToken?

            if viewModel.state.observeChanges {
                token = results.observe { [weak viewModel] changes in
                    guard let viewModel = viewModel else { return }

                    switch changes {
                    case .update(let results, _, _, _):
                        self.update(results: results, viewModel: viewModel)
                    case .error, .initial: break
                    }
                }
            }

            self.sortByColors(tags: &tags)

            self.update(viewModel: viewModel) { state in
                if state.libraryId != libraryId {
                    state.libraryId = libraryId
                }
                
                if clearSelection && !state.selectedTags.isEmpty {
                    state.selectedTags = []
                }

                state.tags = tags
                state.results = results
                state.token = token
                state.changes = [.tags, .selection]
            }
        } catch let error {
            DDLogError("TagPickerStore: can't load tag: \(error)")
            self.update(viewModel: viewModel) { state in
                state.error = .loadingFailed
            }
        }
    }

    private func update(results: Results<RTag>, viewModel: ViewModel<TagPickerActionHandler>) {
        // Create & sort new tags
        var tags = Array(results.map(Tag.init))
        self.sortByColors(tags: &tags)
        // Filter out deleted selections
        var selection = viewModel.state.selectedTags
        for name in viewModel.state.selectedTags {
            if results.filter("name == %@", name).first == nil {
                selection.remove(name)
            }
        }

        self.update(viewModel: viewModel) { state in
            if state.snapshot == nil {
                state.tags = tags
            } else {
                state.snapshot = tags
                state.tags = tags.filter({ $0.name.localizedCaseInsensitiveContains(state.searchTerm) })
                state.showAddTagButton = state.tags.isEmpty || state.tags.first(where: { $0.name == state.searchTerm }) == nil
            }

            state.changes = .tags

            if state.selectedTags != selection {
                state.selectedTags = selection
                state.changes.insert(.selection)
            }
        }
    }

    private func sortByColors(tags: inout [Tag]) {
        var coloredIndices: [Int] = []
        for (index, tag) in tags.enumerated() {
            if !tag.color.isEmpty {
                coloredIndices.append(index)
            }
        }

        var coloredTags: [Tag] = []
        for idx in coloredIndices.reversed() {
            coloredTags.append(tags.remove(at: idx))
        }
        tags.insert(contentsOf: coloredTags, at: 0)
    }
}
