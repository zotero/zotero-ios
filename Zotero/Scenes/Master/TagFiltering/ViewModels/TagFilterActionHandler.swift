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

struct TagFilterActionHandler: ViewModelActionHandler, BackgroundDbProcessingActionHandler {
    typealias Action = TagFilterAction
    typealias State = TagFilterState

    let backgroundQueue: DispatchQueue
    unowned let dbStorage: DbStorage

    init(dbStorage: DbStorage) {
        self.dbStorage = dbStorage
        self.backgroundQueue = DispatchQueue(label: "org.zotero.TagFilterActionHandler.background", qos: .userInitiated)
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

        case .loadWithKeys(let keys, let libraryId):
            self.load(itemKeys: keys, libraryId: libraryId, in: viewModel)

        case .loadWithCollection(let collectionId, let libraryId):
            self.load(collectionId: collectionId, libraryId: libraryId, in: viewModel)

        case .search(let term):
            self.search(with: term, in: viewModel)

        case .add(let name):
            self.add(name: name, in: viewModel)

        case .setDisplayAll(let displayAll):
            guard displayAll != viewModel.state.displayAll else { return }

            Defaults.shared.tagPickerDisplayAllTags = displayAll
            self.update(viewModel: viewModel) { state in
                state.displayAll = displayAll
                state.changes = .options
            }

        case .setShowAutomatic(let showAutomatic):
            guard showAutomatic != viewModel.state.showAutomatic else { return }

            Defaults.shared.tagPickerShowAutomaticTags = showAutomatic
            self.update(viewModel: viewModel) { state in
                state.showAutomatic = showAutomatic
                state.changes = .options
            }

        case .deselectAll:
            self.update(viewModel: viewModel) { state in
                state.selectedTags = []
                state.changes = .selection
            }

        case .deselectAllWithoutNotifying:
            self.update(viewModel: viewModel) { state in
                state.selectedTags = []
            }

        case .loadAutomaticCount(let libraryId):
            let request = ReadAutomaticTagsDbRequest(libraryId: libraryId)
            let count = (try? self.dbStorage.perform(request: request, on: .main))?.count ?? 0
            self.update(viewModel: viewModel) { state in
                state.automaticCount = count
            }

        case .deleteAutomatic(let libraryId):
            self.deleteAutomaticTags(in: libraryId, viewModel: viewModel)

        case .assignTag(let name, let itemKeys, let libraryId):
            self.assign(tagName: name, toItemKeys: itemKeys, libraryId: libraryId, viewModel: viewModel)
        }
    }

    private func assign(tagName: String, toItemKeys keys: Set<String>, libraryId: LibraryIdentifier, viewModel: ViewModel<TagFilterActionHandler>) {
        self.perform(request: AssignItemsToTagDbRequest(keys: keys, libraryId: libraryId, tagName: tagName)) { [weak viewModel] error in
            inMainThread {
                guard let viewModel = viewModel else { return }
                self.update(viewModel: viewModel) { state in
                    state.error = .tagAssignFailed
                }
            }
        }
    }

    private func deleteAutomaticTags(in libraryId: LibraryIdentifier, viewModel: ViewModel<TagFilterActionHandler>) {
        self.perform(request: DeleteAutomaticTagsDbRequest(libraryId: libraryId)) { [weak viewModel] error in
            inMainThread {
                guard let viewModel = viewModel else { return }
                self.update(viewModel: viewModel) { state in
                    state.error = .deletionFailed
                }
            }
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
            }
        }
    }

    private func load(itemKeys: Set<String>, libraryId: LibraryIdentifier, in viewModel: ViewModel<TagFilterActionHandler>) {
        let request = ReadTagsForItemsDbRequest(itemKeys: itemKeys, libraryId: libraryId, showAutomatic: viewModel.state.showAutomatic)
        self.load(filterRequest: request, libraryId: libraryId, in: viewModel)
    }

    private func load(collectionId: CollectionIdentifier, libraryId: LibraryIdentifier, in viewModel: ViewModel<TagFilterActionHandler>) {
        let request = ReadTagsForCollectionDbRequest(collectionId: collectionId, libraryId: libraryId, showAutomatic: viewModel.state.showAutomatic)
        self.load(filterRequest: request, libraryId: libraryId, in: viewModel)
    }

    private func load<Request: DbResponseRequest>(filterRequest: Request, libraryId: LibraryIdentifier, in viewModel: ViewModel<TagFilterActionHandler>) where Request.Response == Results<RTag> {
        do {
            let filtered = (try self.dbStorage.perform(request: filterRequest, on: .main))
            let coloredRequest = ReadColoredTagsDbRequest(libraryId: libraryId)
            let colored = (try self.dbStorage.perform(request: coloredRequest, on: .main)).sorted(by: [SortDescriptor(keyPath: "order", ascending: true),
                                                                                                       SortDescriptor(keyPath: "sortName", ascending: true)])
            let other: Results<RTag>

            if !viewModel.state.displayAll {
                other = filtered.filter("color = \"\"").sorted(byKeyPath: "sortName")
            } else {
                let otherRequest = ReadTagsForCollectionDbRequest(collectionId: .custom(.all), libraryId: libraryId, showAutomatic: viewModel.state.showAutomatic)
                other = (try self.dbStorage.perform(request: otherRequest, on: .main)).filter("color = \"\"").sorted(byKeyPath: "sortName")
            }

            var selected: Set<String> = []
            // Update selection based on current filter to exclude selected tags which were filtered out by some change.
            let filteredSelected = filtered.filter(.name(in: viewModel.state.selectedTags))
            for tag in filteredSelected {
                selected.insert(tag.name)
            }

            self.update(viewModel: viewModel) { state in
                state.coloredResults = colored
                state.otherResults = other
                state.filteredResults = filtered
                state.changes = .tags
                state.selectedTags = selected
            }
        } catch let error {
            DDLogError("TagFilterActionHandler: can't load tag: \(error)")
            self.update(viewModel: viewModel) { state in
                state.error = .loadingFailed
            }
        }
    }
}

