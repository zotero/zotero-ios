//
//  ItemsActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 21/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjack

struct ItemsActionHandler: ViewModelActionHandler {
    typealias State = ItemsState
    typealias Action = ItemsAction

    private let dbStorage: DbStorage
    private let fileStorage: FileStorage
    private let schemaController: SchemaController
    private let backgroundQueue: DispatchQueue

    init(dbStorage: DbStorage, fileStorage: FileStorage, schemaController: SchemaController) {
        self.backgroundQueue = DispatchQueue.global(qos: .userInitiated)
        self.dbStorage = dbStorage
        self.fileStorage = fileStorage
        self.schemaController = schemaController
    }

    func process(action: ItemsAction, in viewModel: ViewModel<ItemsActionHandler>) {
        switch action {
        case .addAttachments(let urls):
            self.addAttachments(urls: urls, in: viewModel)

        case .assignSelectedItemsToCollections(let collections):
            self.addSelectedItems(to: collections, in: viewModel)

        case .deselectItem(let key):
            self.update(viewModel: viewModel) { state in
                state.selectedItems.remove(key)
                state.changes.insert(.selection)
            }

        case .selectItem(let key):
            self.update(viewModel: viewModel) { state in
                state.selectedItems.insert(key)
                state.changes.insert(.selection)
            }

        case .loadItemToDuplicate(let key):
            self.loadItemForDuplication(key: key, in: viewModel)

        case .moveItems(let fromKeys, let toKey):
            self.moveItems(from: fromKeys, to: toKey, in: viewModel)

        case .observingFailed:
            self.update(viewModel: viewModel) { state in
                state.error = .dataLoading
            }

        case .saveNote(let key, let text):
            if let key = key {
                self.saveNote(text: text, key: key, in: viewModel)
            } else {
                self.createNote(with: text, in: viewModel)
            }

        case .search(let text):
            self.search(for: text, in: viewModel)

        case .setSortField(let field):
            var sortType = viewModel.state.sortType
            sortType.field = field
            self.changeSortType(to: sortType, in: viewModel)

        case .startEditing:
            self.update(viewModel: viewModel) { state in
                state.isEditing = true
                state.changes.insert(.editing)
            }

        case .stopEditing:
            self.update(viewModel: viewModel) { state in
                state.isEditing = false
                state.selectedItems.removeAll()
                state.changes.insert(.editing)
            }

        case .toggleSortOrder:
            var sortType = viewModel.state.sortType
            sortType.ascending.toggle()
            self.changeSortType(to: sortType, in: viewModel)

        case .trashSelectedItems:
            self.setTrashedToSelectedItems(trashed: true, in: viewModel)

        case .restoreSelectedItems:
            self.setTrashedToSelectedItems(trashed: false, in: viewModel)

        case .deleteSelectedItems:
            self.deleteSelectedItems(in: viewModel)
        }
    }

    private func deleteSelectedItems(in viewModel: ViewModel<ItemsActionHandler>) {
        let request = DeleteObjectsDbRequest<RItem>(keys: Array(viewModel.state.selectedItems),
                                                    libraryId: viewModel.state.library.identifier)
        self.perform(request: request) { [weak viewModel] error in
            guard let viewModel = viewModel else { return }
            DDLogError("ItemsStore: can't delete items - \(error)")
            self.update(viewModel: viewModel) { state in
                state.error = .deletion
            }
        }
    }

    private func setTrashedToSelectedItems(trashed: Bool, in viewModel: ViewModel<ItemsActionHandler>) {
        let request = MarkItemsAsTrashedDbRequest(keys: Array(viewModel.state.selectedItems),
                                                  libraryId: viewModel.state.library.identifier,
                                                  trashed: trashed)
        self.perform(request: request) { [weak viewModel] error in
            guard let viewModel = viewModel else { return }
            DDLogError("ItemsStore: can't trash items - \(error)")
            self.update(viewModel: viewModel) { state in
                state.error = .deletion
            }
        }
    }

    private func changeSortType(to sortType: ItemsSortType, in viewModel: ViewModel<ItemsActionHandler>) {
        self.update(viewModel: viewModel) { state in
            state.sortType = sortType
            let descriptors = state.sortType.descriptors
            state.results = state.results?.sorted(by: descriptors)
            state.unfilteredResults = state.unfilteredResults?.sorted(by: descriptors)
            state.changes.insert(.sortType)
        }
    }

    private func moveItems(from keys: [String], to key: String, in viewModel: ViewModel<ItemsActionHandler>) {
        let request = MoveItemsToParentDbRequest(itemKeys: keys, parentKey: key, libraryId: viewModel.state.library.identifier)
        self.perform(request: request) { [weak viewModel] error in
            guard let viewModel = viewModel else { return }
            DDLogError("ItemsStore: can't move items to parent: \(error)")
            self.update(viewModel: viewModel) { state in
                state.error = .itemMove
            }
        }
    }

    private func createNote(with text: String, in viewModel: ViewModel<ItemsActionHandler>) {
        let note = Note(key: KeyGenerator.newKey, text: text)
        let request = CreateNoteDbRequest(note: note,
                                          localizedType: (self.schemaController.localized(itemType: ItemTypes.note) ?? ""),
                                          libraryId: viewModel.state.library.identifier)
        self.perform(request: request) { [weak viewModel] error in
            guard let viewModel = viewModel else { return }
            DDLogError("ItemsStore: can't save new note: \(error)")
            self.update(viewModel: viewModel) { state in
                state.error = .noteSaving
            }
        }
    }

    private func saveNote(text: String, key: String, in viewModel: ViewModel<ItemsActionHandler>) {
        let note = Note(key: key, text: text)
        let request = StoreNoteDbRequest(note: note, libraryId: viewModel.state.library.identifier)
        self.perform(request: request) { [weak viewModel] error in
            guard let viewModel = viewModel else { return }
            DDLogError("ItemsStore: can't save note: \(error)")
            self.update(viewModel: viewModel) { state in
                state.error = .noteSaving
            }
        }
    }

    private func search(for text: String, in viewModel: ViewModel<ItemsActionHandler>) {
        if text.isEmpty {
            self.removeResultsFilters(in: viewModel)
        } else {
            self.filterResults(with: text, in: viewModel)
        }
    }

    private func filterResults(with text: String, in viewModel: ViewModel<ItemsActionHandler>) {
        self.update(viewModel: viewModel) { state in
            if state.unfilteredResults == nil {
                state.unfilteredResults = state.results
            }
            state.results = state.unfilteredResults?.filter(.itemSearch(for: text))
            state.changes.insert(.results)
        }
    }

    private func removeResultsFilters(in viewModel: ViewModel<ItemsActionHandler>) {
        self.update(viewModel: viewModel) { state in
            guard state.unfilteredResults != nil else { return }
            state.results = state.unfilteredResults
            state.changes.insert(.results)
            state.unfilteredResults = nil
        }
    }

    private func addSelectedItems(to collectionKeys: Set<String>, in viewModel: ViewModel<ItemsActionHandler>) {
        let request = AssignItemsToCollectionsDbRequest(collectionKeys: collectionKeys,
                                                        itemKeys: viewModel.state.selectedItems,
                                                        libraryId: viewModel.state.library.identifier)
        self.perform(request: request) { [weak viewModel] error in
            guard let viewModel = viewModel else { return }
            DDLogError("ItemsStore: can't assign collections to items - \(error)")
            self.update(viewModel: viewModel) { state in
                state.error = .collectionAssignment
            }
        }
    }

    private func addAttachments(urls: [URL], in viewModel: ViewModel<ItemsActionHandler>) {
        self.backgroundQueue.async { [weak viewModel] in
            guard let viewModel = viewModel else { return }
            self._addAttachments(urls: urls, in: viewModel)
        }
    }

    private func _addAttachments(urls: [URL], in viewModel: ViewModel<ItemsActionHandler>) {
        let attachments = urls.map({ Files.file(from: $0) })
                              .map({
                                  Attachment(key: KeyGenerator.newKey,
                                             title: $0.name,
                                             type: .file(file: $0, filename: $0.name, isLocal: true),
                                             libraryId: viewModel.state.library.identifier)
                              })

        do {
            try self.fileStorage.copyAttachmentFilesIfNeeded(for: attachments)

            let type = self.schemaController.localized(itemType: ItemTypes.attachment) ?? ""
            let request = CreateAttachmentsDbRequest(attachments: attachments, localizedType: type)
            let failedTitles = try self.dbStorage.createCoordinator().perform(request: request)

            if !failedTitles.isEmpty {
                self.update(viewModel: viewModel) { state in
                    state.error = .attachmentAdding(.someFailed(failedTitles))
                }
            }
        } catch let error {
            DDLogError("ItemsStore: can't add attachment: \(error)")
            self.update(viewModel: viewModel) { state in
                state.error = .attachmentAdding(.couldNotSave)
            }
        }
    }

    private func loadItemForDuplication(key: String, in viewModel: ViewModel<ItemsActionHandler>) {
        let request = ReadItemDbRequest(libraryId: viewModel.state.library.identifier, key: key)

        do {
            let item = try self.dbStorage.createCoordinator().perform(request: request)
            self.update(viewModel: viewModel) { state in
                state.itemDuplication = item
                state.isEditing = false
                state.selectedItems.removeAll()
                state.changes.insert(.editing)
            }
        } catch let error {
            self.update(viewModel: viewModel) { state in
                state.error = .duplicationLoading
            }
        }
    }

    private func perform<Request: DbResponseRequest>(request: Request, errorAction: @escaping (Swift.Error) -> Void) {
        self.backgroundQueue.async {
            do {
                _ = try self.dbStorage.createCoordinator().perform(request: request)
            } catch let error {
                errorAction(error)
            }
        }
    }

    private func perform<Request: DbRequest>(request: Request, errorAction: @escaping (Swift.Error) -> Void) {
        self.backgroundQueue.async {
            do {
                try self.dbStorage.createCoordinator().perform(request: request)
            } catch let error {
                errorAction(error)
            }
        }
    }
}
