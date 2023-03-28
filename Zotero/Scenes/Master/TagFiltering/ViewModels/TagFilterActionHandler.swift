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
            self.load(libraryId: viewModel.state.libraryId, collectionId: viewModel.state.collectionId, clearSelection: false, in: viewModel)

        case .deselect(let name):
            self.update(viewModel: viewModel) { state in
                state.selectedTags.remove(name)
                state.changes = .selection
            }
            self.load(libraryId: viewModel.state.libraryId, collectionId: viewModel.state.collectionId, clearSelection: false, in: viewModel)

        case .load(let libraryId, let collectionId, let clearSelection):
            self.load(libraryId: libraryId, collectionId: collectionId, clearSelection: clearSelection, in: viewModel)

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
//        if !term.isEmpty {
//            self.update(viewModel: viewModel) { state in
//                if state.snapshot == nil {
//                    state.snapshot = state.tags
//                }
//                state.searchTerm = term
//                state.tags = (state.snapshot ?? state.tags).filter({ $0.name.localizedCaseInsensitiveContains(term) })
//                state.changes = .tags
//                state.showAddTagButton = state.tags.isEmpty || state.tags.first(where: { $0.name == term }) == nil
//            }
//        } else {
//            guard let snapshot = viewModel.state.snapshot else { return }
//            self.update(viewModel: viewModel) { state in
//                state.tags = snapshot
//                state.snapshot = nil
//                state.searchTerm = ""
//                state.changes = .tags
//                state.showAddTagButton = false
//            }
//        }
    }

    private func load(libraryId: LibraryIdentifier, collectionId: CollectionIdentifier, clearSelection: Bool, in viewModel: ViewModel<TagFilterActionHandler>) {
        do {
            let request = ReadFilterTagsDbRequest(libraryId: libraryId, collectionId: collectionId, selectedNames: (clearSelection ? [] : viewModel.state.selectedTags))
            let results = try self.dbStorage.perform(request: request, on: .main)
            let colored = results.filter("color != \"\"").sorted(byKeyPath: "name")
            let other = results.filter("color = \"\"").sorted(byKeyPath: "name")

            let coloredToken = colored.observe { [weak viewModel] change in
                guard let viewModel = viewModel else { return }
                switch change {
                case .update(let results, let deletions, let insertions, let modifications):
                    self.update(viewModel: viewModel) { state in
                        state.coloredChange = TagFilterState.ObservedChange(results: results, modifications: modifications, insertions: insertions, deletions: deletions)
                    }
                default: break
                }
            }

            let otherToken = other.observe { [weak viewModel] change in
                guard let viewModel = viewModel else { return }
                switch change {
                case .update(let results, let deletions, let insertions, let modifications):
                    self.update(viewModel: viewModel) { state in
                        state.otherChange = TagFilterState.ObservedChange(results: results, modifications: modifications, insertions: insertions, deletions: deletions)
                    }
                default: break
                }
            }

            self.update(viewModel: viewModel) { state in
                state.libraryId = libraryId
                state.collectionId = collectionId
                state.coloredResults = colored
                state.coloredNotificationToken = coloredToken
                state.otherResults = other
                state.otherNotificationToken = otherToken
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

