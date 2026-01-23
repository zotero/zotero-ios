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
    let dbStorage: DbStorage

    init(dbStorage: DbStorage) {
        self.dbStorage = dbStorage
        backgroundQueue = DispatchQueue(label: "org.zotero.TagFilterActionHandler.background", qos: .userInitiated)
    }

    func process(action: TagFilterAction, in viewModel: ViewModel<TagFilterActionHandler>) {
        switch action {
        case .select(let name):
            update(viewModel: viewModel) { state in
                state.selectedTags.insert(name)
                state.changes = .selection
            }

        case .deselect(let name):
            update(viewModel: viewModel) { state in
                state.selectedTags.remove(name)
                state.changes = .selection
            }

        case .load(let itemFilters, let collectionId, let libraryId):
            load(with: itemFilters, collectionId: collectionId, libraryId: libraryId, in: viewModel)

        case .search(let term):
            search(with: term, in: viewModel)

        case .setDisplayAll(let displayAll):
            guard displayAll != viewModel.state.displayAll else { return }

            Defaults.shared.tagPickerDisplayAllTags = displayAll
            update(viewModel: viewModel) { state in
                state.displayAll = displayAll
                state.changes = .options
            }

        case .setShowAutomatic(let showAutomatic):
            guard showAutomatic != viewModel.state.showAutomatic else { return }

            Defaults.shared.tagPickerShowAutomaticTags = showAutomatic
            update(viewModel: viewModel) { state in
                state.showAutomatic = showAutomatic
                state.changes = .options
            }

        case .deselectAll:
            update(viewModel: viewModel) { state in
                state.selectedTags = []
                state.changes = .selection
            }

        case .deselectAllWithoutNotifying:
            update(viewModel: viewModel) { state in
                state.selectedTags = []
            }

        case .loadAutomaticCount(let libraryId):
            let request = ReadAutomaticTagsDbRequest(libraryId: libraryId)
            let count = (try? dbStorage.perform(request: request, on: .main))?.count ?? 0
            update(viewModel: viewModel) { state in
                state.automaticCount = count
            }

        case .deleteAutomatic(let libraryId):
            deleteAutomaticTags(in: libraryId, viewModel: viewModel)

        case .assignTag(let name, let itemKeys, let libraryId):
            assign(tagName: name, toItemKeys: itemKeys, libraryId: libraryId, viewModel: viewModel)
        }
    }

    private func assign(tagName: String, toItemKeys keys: Set<String>, libraryId: LibraryIdentifier, viewModel: ViewModel<TagFilterActionHandler>) {
        perform(request: AssignItemsToTagDbRequest(keys: keys, libraryId: libraryId, tagName: tagName)) { [weak viewModel] _ in
            inMainThread {
                guard let viewModel else { return }
                update(viewModel: viewModel) { state in
                    state.error = .tagAssignFailed
                }
            }
        }
    }

    private func deleteAutomaticTags(in libraryId: LibraryIdentifier, viewModel: ViewModel<TagFilterActionHandler>) {
        perform(request: DeleteAutomaticTagsDbRequest(libraryId: libraryId)) { [weak viewModel] _ in
            inMainThread {
                guard let viewModel else { return }
                update(viewModel: viewModel) { state in
                    state.error = .deletionFailed
                }
            }
        }
    }

    private func search(with term: String, in viewModel: ViewModel<TagFilterActionHandler>) {
        if !term.isEmpty {
            let filtered = viewModel.state.tags.filter({ $0.tag.name.localizedCaseInsensitiveContains(term) })
            update(viewModel: viewModel) { state in
                if state.snapshot == nil {
                    state.snapshot = state.tags
                }
                state.tags = filtered
                state.searchTerm = term
                state.changes = .tags
            }
        } else {
            guard let snapshot = viewModel.state.snapshot else { return }
            update(viewModel: viewModel) { state in
                state.tags = snapshot
                state.snapshot = nil
                state.searchTerm = ""
                state.changes = .tags
            }
        }
    }

    private func load(with filters: [ItemsFilter], collectionId: CollectionIdentifier, libraryId: LibraryIdentifier, in viewModel: ViewModel<TagFilterActionHandler>) {
        // Creating local copies of required state properties, so we avoid an exclusivity violation, if the main thread updates the state while the background queue reads it at the same time.
        let showAutomatic = viewModel.state.showAutomatic
        let selectedTags = viewModel.state.selectedTags
        let displayAll = viewModel.state.displayAll
        let searchTerm = viewModel.state.searchTerm
        backgroundQueue.async { [weak viewModel] in
            guard let viewModel else { return }
            _load(
                with: filters,
                collectionId: collectionId,
                libraryId: libraryId,
                showAutomatic: showAutomatic,
                selectedTags: selectedTags,
                displayAll: displayAll,
                searchTerm: searchTerm,
                in: viewModel
            )
        }
    }

    private func _load(
        with filters: [ItemsFilter],
        collectionId: CollectionIdentifier,
        libraryId: LibraryIdentifier,
        showAutomatic: Bool,
        selectedTags: Set<String>,
        displayAll: Bool,
        searchTerm: String,
        in viewModel: ViewModel<TagFilterActionHandler>
    ) {
        do {
            var selected: Set<String> = []
            var snapshot: [TagFilterState.FilterTag]?
            var sorted: [TagFilterState.FilterTag] = []
            let comparator: (TagFilterState.FilterTag, TagFilterState.FilterTag) -> Bool = {
                return $0.tag.name.localizedCaseInsensitiveCompare($1.tag.name) == .orderedAscending
            }

            try dbStorage.perform(on: backgroundQueue) { [weak viewModel] coordinator in
                guard viewModel != nil else {
                    coordinator.invalidate()
                    return
                }
                let filtered = try coordinator.perform(
                    request: ReadFilteredTagsDbRequest(collectionId: collectionId, libraryId: libraryId, showAutomatic: showAutomatic, filters: filters)
                )
                let colored = try coordinator.perform(request: ReadColoredTagsDbRequest(libraryId: libraryId))
                let emoji = try coordinator.perform(request: ReadEmojiTagsDbRequest(libraryId: libraryId))

                // Update selection based on current filter to exclude selected tags which were filtered out by some change.
                for tag in filtered {
                    guard selectedTags.contains(tag.name) else { continue }
                    selected.insert(tag.name)
                }

                // Add colored tags
                var sortedColored: [TagFilterState.FilterTag] = []
                for rTag in colored.sorted(byKeyPath: "order") {
                    let tag = Tag(tag: rTag)
                    let isActive = filtered.contains(tag)
                    let filterTag = TagFilterState.FilterTag(tag: tag, isActive: isActive)
                    sortedColored.append(filterTag)
                }
                sorted.append(contentsOf: sortedColored)

                // Add emoji tags
                var sortedEmoji: [TagFilterState.FilterTag] = []
                for rTag in emoji {
                    let tag = Tag(tag: rTag)
                    let isActive = filtered.contains(tag)
                    let filterTag = TagFilterState.FilterTag(tag: tag, isActive: isActive)
                    let index = sortedEmoji.index(of: filterTag, sortedBy: comparator)
                    sortedEmoji.insert(filterTag, at: index)
                }
                sorted.append(contentsOf: sortedEmoji)

                var sortedOther: [TagFilterState.FilterTag] = []
                if !displayAll {
                    // Add remaining filtered tags, ignore colored
                    for tag in filtered {
                        guard tag.color.isEmpty && tag.emojiGroup == nil else { continue }
                        let filterTag = TagFilterState.FilterTag(tag: tag, isActive: true)
                        let index = sortedOther.index(of: filterTag, sortedBy: comparator)
                        sortedOther.insert(filterTag, at: index)
                    }
                } else {
                    // Add all remaining tags with proper isActive flag
                    let tags = try coordinator.perform(request: ReadFilteredTagsDbRequest(collectionId: .custom(.all), libraryId: libraryId, showAutomatic: showAutomatic, filters: []))
                    for tag in tags {
                        guard tag.color.isEmpty && tag.emojiGroup == nil else { continue }
                        let isActive = filtered.contains(tag)
                        let filterTag = TagFilterState.FilterTag(tag: tag, isActive: isActive)
                        let index = sortedOther.index(of: filterTag, sortedBy: comparator)
                        sortedOther.insert(filterTag, at: index)
                    }
                }
                sorted.append(contentsOf: sortedOther)

                coordinator.invalidate()

                if !searchTerm.isEmpty {
                    // Perform search filter if needed
                    snapshot = sorted
                    sorted = sorted.filter({ $0.tag.name.localizedCaseInsensitiveContains(searchTerm) })
                }
            }

            inMainThread { [weak viewModel] in
                guard let viewModel else { return }
                update(viewModel: viewModel) { state in
                    state.tags = sorted
                    state.snapshot = snapshot
                    state.changes = .tags
                    state.selectedTags = selected
                }
            }
        } catch let error {
            inMainThread { [weak viewModel] in
                guard let viewModel else { return }
                DDLogError("TagFilterActionHandler: can't load tag: \(error)")
                update(viewModel: viewModel) { state in
                    state.error = .loadingFailed
                }
            }
        }
    }
}
