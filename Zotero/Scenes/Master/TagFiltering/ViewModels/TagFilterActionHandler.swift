//
//  TagFilterActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 22.03.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RealmSwift

struct TagFilterActionHandler: ViewModelActionHandler {
    typealias Action = TagFilterAction
    typealias State = TagFilterState

    private unowned let dbStorage: DbStorage

    init(dbStorage: DbStorage) {
        self.dbStorage = dbStorage
    }

    func process(action: TagFilterAction, in viewModel: ViewModel<TagFilterActionHandler>) {
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

        case .loadWithKeys(let keys, let libraryId, let clearSelection):
            self.load(itemKeys: keys, libraryId: libraryId, clearSelection: clearSelection, in: viewModel)

        case .loadWithCollection(let collectionId, let libraryId, let clearSelection):
            self.load(collectionId: collectionId, libraryId: libraryId, clearSelection: clearSelection, in: viewModel)

        case .search(let term):
            self.search(with: term, in: viewModel)

        case .add(let name):
            self.add(name: name, in: viewModel)
        }
    }

    private func add(name: String, in viewModel: ViewModel<TagFilterActionHandler>) {
//        guard let snapshot = viewModel.state.snapshot else { return }
//        self.update(viewModel: viewModel) { state in
//            let tag = Tag(name: name, color: "")
//            state.tags = snapshot
//
//            let index = state.tags.index(of: tag, sortedBy: { $0.name.caseInsensitiveCompare($1.name) == .orderedAscending })
//            state.tags.insert(tag, at: index)
//            state.selectedTags.insert(name)
//
//            state.snapshot = nil
//            state.searchTerm = ""
//            state.addedTagName = name
//            state.showAddTagButton = false
//            state.changes = [.tags, .selection]
//        }
    }

    private func search(with term: String, in viewModel: ViewModel<TagFilterActionHandler>) {
        if !term.isEmpty {
            self.update(viewModel: viewModel) { state in
                if state.coloredSnapshot == nil {
                    state.coloredSnapshot = state.coloredResults
                }
                if state.otherSnapshot == nil {
                    state.otherSnapshot = state.otherResults
                }
                state.coloredResults = state.coloredSnapshot?.filter("name contains[c] %@", term)
                state.otherResults = state.otherSnapshot?.filter("name contains[c] %@", term)
                state.searchTerm = term
                state.changes = .tags
//                state.showAddTagButton = state.tags.isEmpty || state.tags.first(where: { $0.name == term }) == nil
            }
        } else {
            guard let coloredSnapshot = viewModel.state.coloredSnapshot, let otherSnapshot = viewModel.state.otherSnapshot else { return }
            self.update(viewModel: viewModel) { state in
                state.coloredResults = coloredSnapshot
                state.otherResults = otherSnapshot
                state.coloredSnapshot = nil
                state.otherSnapshot = nil
                state.searchTerm = ""
                state.changes = .tags
//                state.showAddTagButton = false
            }
        }
    }

    private func load(itemKeys: Set<String>, libraryId: LibraryIdentifier, clearSelection: Bool, in viewModel: ViewModel<TagFilterActionHandler>) {
        let request = ReadTagsForItemsDbRequest(itemKeys: itemKeys, libraryId: libraryId)
        self.load(filterRequest: request, libraryId: libraryId, clearSelection: clearSelection, in: viewModel)
    }

    private func load(collectionId: CollectionIdentifier, libraryId: LibraryIdentifier, clearSelection: Bool, in viewModel: ViewModel<TagFilterActionHandler>) {
        let request = ReadTagsForCollectionDbRequest(collectionId: collectionId, libraryId: libraryId)
        self.load(filterRequest: request, libraryId: libraryId, clearSelection: clearSelection, in: viewModel)
    }

    private func load<Request: DbResponseRequest>(filterRequest: Request, libraryId: LibraryIdentifier, clearSelection: Bool, in viewModel: ViewModel<TagFilterActionHandler>) where Request.Response == Results<RTag> {
        do {
            let filtered = (try self.dbStorage.perform(request: filterRequest, on: .main)).sorted(byKeyPath: "name")
            let coloredRequest = ReadColoredTagsDbRequest(libraryId: libraryId)
            let colored = (try self.dbStorage.perform(request: coloredRequest, on: .main)).sorted(byKeyPath: "name")
            let other = filtered.filter("color = \"\"")

            let coloredToken = colored.observe { [weak viewModel] change in
                // Don't update when search is active
                guard let viewModel = viewModel, viewModel.state.coloredSnapshot == nil else { return }
                switch change {
                case .update(let results, let deletions, let insertions, let modifications):
                    self.update(viewModel: viewModel) { state in
                        state.coloredChange = TagFilterState.ObservedChange(results: results, modifications: modifications, insertions: insertions, deletions: deletions)
                    }
                default: break
                }
            }

            let otherToken = other.observe { [weak viewModel] change in
                // Don't update when search is active
                guard let viewModel = viewModel, viewModel.state.otherSnapshot == nil else { return }
                switch change {
                case .update(let results, let deletions, let insertions, let modifications):
                    self.update(viewModel: viewModel) { state in
                        state.otherChange = TagFilterState.ObservedChange(results: results, modifications: modifications, insertions: insertions, deletions: deletions)
                    }
                default: break
                }
            }

            self.update(viewModel: viewModel) { state in
                state.coloredResults = colored
                state.coloredNotificationToken = coloredToken
                state.otherResults = other
                state.otherNotificationToken = otherToken
                state.filteredResults = filtered
                state.changes = .tags

                if clearSelection {
                    state.selectedTags = []
                    state.changes.insert(.selection)
                }
            }
        } catch let error {
            DDLogError("TagFilterActionHandler: can't load tag: \(error)")
            self.update(viewModel: viewModel) { state in
                state.error = .loadingFailed
            }
        }
    }
}

