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

        case .load(let itemFilters, let collectionId, let libraryId):
            self.load(with: itemFilters, collectionId: collectionId, libraryId: libraryId, in: viewModel)

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
            let filtered = viewModel.state.tags.filter({ $0.tag.name.localizedCaseInsensitiveContains(term) })
            self.update(viewModel: viewModel) { state in
                if state.snapshot == nil {
                    state.snapshot = state.tags
                }
                state.tags = filtered
                state.searchTerm = term
                state.changes = .tags
            }
        } else {
            guard let snapshot = viewModel.state.snapshot else { return }
            self.update(viewModel: viewModel) { state in
                state.tags = snapshot
                state.snapshot = nil
                state.searchTerm = ""
                state.changes = .tags
            }
        }
    }

    private func load(with filters: [ItemsFilter], collectionId: CollectionIdentifier, libraryId: LibraryIdentifier, in viewModel: ViewModel<TagFilterActionHandler>) {
        self.backgroundQueue.async { [weak viewModel] in
            guard let viewModel = viewModel else { return }
            self._load(with: filters, collectionId: collectionId, libraryId: libraryId, in: viewModel)
        }
    }

    private func _load(with filters: [ItemsFilter], collectionId: CollectionIdentifier, libraryId: LibraryIdentifier, in viewModel: ViewModel<TagFilterActionHandler>) {
        do {
            var selected: Set<String> = []
            var snapshot: [TagFilterState.FilterTag]? = nil
            var sorted: [TagFilterState.FilterTag] = []
            let comparator: (TagFilterState.FilterTag, TagFilterState.FilterTag) -> Bool = {
                if !$0.tag.color.isEmpty && $1.tag.color.isEmpty {
                    return true
                }
                if $0.tag.color.isEmpty && !$1.tag.color.isEmpty {
                    return false
                }
                return $0.tag.name.localizedCaseInsensitiveCompare($1.tag.name) == .orderedAscending
            }

            try self.dbStorage.perform(on: self.backgroundQueue) { coordinator in
                let filtered = try coordinator.perform(request: ReadFilteredTagsDbRequest(collectionId: collectionId, libraryId: libraryId, showAutomatic: viewModel.state.showAutomatic, filters: filters))
                let colored = try coordinator.perform(request: ReadColoredTagsDbRequest(libraryId: libraryId))

                // Update selection based on current filter to exclude selected tags which were filtered out by some change.
                for tag in filtered {
                    guard viewModel.state.selectedTags.contains(tag.name) else { continue }
                    selected.insert(tag.name)
                }

                // Add colored tags
                for rTag in colored {
                    let tag = Tag(tag: rTag)
                    let isActive = filtered.contains(tag)
                    let filterTag = TagFilterState.FilterTag(tag: tag, isActive: isActive)
                    let index = sorted.index(of: filterTag, sortedBy: comparator)
                    sorted.insert(filterTag, at: index)
                }

                if !viewModel.state.displayAll {
                    // Add remaining filtered tags, ignore colored
                    for tag in filtered {
                        guard tag.color.isEmpty else { continue }
                        let filterTag = TagFilterState.FilterTag(tag: tag, isActive: true)
                        let index = sorted.index(of: filterTag, sortedBy: comparator)
                        sorted.insert(filterTag, at: index)
                    }
                } else {
                    // Add all remaining tags with proper isActive flag
                    let tags = try coordinator.perform(request: ReadFilteredTagsDbRequest(collectionId: collectionId, libraryId: libraryId, showAutomatic: viewModel.state.showAutomatic, filters: []))
                    for tag in tags {
                        guard tag.color.isEmpty else { continue }
                        let isActive = filtered.contains(tag)
                        let filterTag = TagFilterState.FilterTag(tag: tag, isActive: isActive)
                        let index = sorted.index(of: filterTag, sortedBy: comparator)
                        sorted.insert(filterTag, at: index)
                    }
                }

                coordinator.invalidate()

                if !viewModel.state.searchTerm.isEmpty {
                    // Perform search filter if needed
                    snapshot = sorted
                    sorted = sorted.filter({ $0.tag.name.localizedCaseInsensitiveContains(viewModel.state.searchTerm) })
                }
            }

            inMainThread { [weak viewModel] in
                guard let viewModel = viewModel else { return }
                self.update(viewModel: viewModel) { state in
                    state.tags = sorted
                    state.snapshot = snapshot
                    state.changes = .tags
                    state.selectedTags = selected
                }
            }
        } catch let error {
            inMainThread { [weak viewModel] in
                guard let viewModel = viewModel else { return }
                DDLogError("TagFilterActionHandler: can't load tag: \(error)")
                self.update(viewModel: viewModel) { state in
                    state.error = .loadingFailed
                }
            }
        }
    }
}

