//
//  ItemsActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 21/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RealmSwift

struct ItemsActionHandler: ViewModelActionHandler {
    typealias State = ItemsState
    typealias Action = ItemsAction

    private unowned let dbStorage: DbStorage
    private unowned let fileStorage: FileStorage
    private unowned let schemaController: SchemaController
    private unowned let urlDetector: UrlDetector
    private unowned let backgroundQueue: DispatchQueue
    private unowned let fileDownloader: FileDownloader

    init(dbStorage: DbStorage, fileStorage: FileStorage, schemaController: SchemaController, urlDetector: UrlDetector, fileDownloader: FileDownloader) {
        self.backgroundQueue = DispatchQueue.global(qos: .userInitiated)
        self.dbStorage = dbStorage
        self.fileStorage = fileStorage
        self.schemaController = schemaController
        self.urlDetector = urlDetector
        self.fileDownloader = fileDownloader
    }

    func process(action: ItemsAction, in viewModel: ViewModel<ItemsActionHandler>) {
        switch action {
        case .addAttachments(let urls):
            self.addAttachments(urls: urls, in: viewModel)

        case .assignItemsToCollections(let items, let collections):
            self.add(items: items, to: collections, in: viewModel)

        case .deleteItemsFromCollection(let keys):
            self.deleteItemsFromCollection(keys: keys, in: viewModel)

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
            self.search(for: (text.isEmpty ? nil : text), in: viewModel)

        case .setSortField(let field):
            var sortType = viewModel.state.sortType
            sortType.field = field
            self.changeSortType(to: sortType, in: viewModel)

        case .startEditing:
            self.startEditing(in: viewModel)

        case .stopEditing:
            self.update(viewModel: viewModel) { state in
                self.stopEditing(in: &state)
            }

        case .toggleSortOrder:
            var sortType = viewModel.state.sortType
            sortType.ascending.toggle()
            self.changeSortType(to: sortType, in: viewModel)

        case .trashItems(let keys):
            self.set(trashed: true, to: keys, in: viewModel)

        case .restoreItems(let keys):
            self.set(trashed: false, to: keys, in: viewModel)

        case .deleteItems(let keys):
            self.delete(items: keys, in: viewModel)

        case .loadInitialState:
            self.loadInitialState(in: viewModel)

        case .toggleSelectionState:
            self.update(viewModel: viewModel) { state in
                if state.selectedItems.count != state.results?.count {
                    state.selectedItems = Set(state.results?.map({ $0.key }) ?? [])
                } else {
                    state.selectedItems = []
                }
                state.changes = [.selection, .selectAll]
            }

        case .cacheAttachment(let item):
            self.cacheAttachment(for: item, in: viewModel)

        case .updateKeys(let items, let deletions, let insertions, let modifications):
            self.processUpdate(items: items, deletions: deletions, insertions: insertions, modifications: modifications, in: viewModel)

        case .updateDownload(let update):
            self.process(downloadUpdate: update, in: viewModel)

        case .openAttachment(let key, let parentKey):
            self.openAttachment(for: key, parentKey: parentKey, in: viewModel)

        case .updateAttachments(let notification):
            self.updateDeletedAttachments(notification, in: viewModel)

        case .filter(let filters):
            self.filter(with: filters, in: viewModel)
        }
    }

    private func loadInitialState(in viewModel: ViewModel<ItemsActionHandler>) {
        let sortType = Defaults.shared.itemsSortType
        let request = ReadItemsDbRequest(type: viewModel.state.type, libraryId: viewModel.state.library.identifier)
        let results = try? self.dbStorage.createCoordinator().perform(request: request).sorted(by: sortType.descriptors)

        self.update(viewModel: viewModel) { state in
            state.results = results
            state.sortType = sortType
            state.error = (results == nil ? .dataLoading : nil)
        }
    }

    // MARK: - Attachments

    private func updateDeletedAttachments(_ notification: AttachmentFileDeletedNotification, in viewModel: ViewModel<ItemsActionHandler>) {
        self.update(viewModel: viewModel) { state in
            // Simply remove deleted attachments from cache, they will be re-cached on demand with proper settings
            switch notification {
            case .all:
                state.attachments = [:]
                state.changes = .attachmentsRemoved
            case .library(let libraryId):
                if libraryId == state.library.identifier {
                    state.attachments = [:]
                    state.changes = .attachmentsRemoved
                }
            case .individual(_, let parentKey, let libraryId):
                // Find item whose mainAttachment has the `key`, for which the file was deleted. If the item was found, new `Attachment`
                // (with updated content type and availability) is created from items `attachment`.
                if libraryId == state.library.identifier, let parentKey = parentKey {
                    // Clear attachment so that it's re-cached when needed.
                    state.attachments[parentKey] = state.results?.filter(.key(parentKey)).first.flatMap({ $0.attachment }).flatMap({
                        AttachmentCreator.attachment(for: $0, fileStorage: self.fileStorage, urlDetector: self.urlDetector)
                    })
                    state.updateItemKey = parentKey
                }
            }
        }
    }

    private func openAttachment(for key: String, parentKey: String, in viewModel: ViewModel<ItemsActionHandler>) {
        guard let attachment = viewModel.state.attachments[parentKey] else { return }

        switch attachment.contentType {
        case .url:
            self.update(viewModel: viewModel) { state in
                state.openAttachment = (attachment, parentKey)
            }
        case .file(let file, _, let location, _),
             .snapshot(_, _, let file, let location):
            guard let location = location else { return }

            switch location {
            case .local:
                self.update(viewModel: viewModel) { state in
                    state.openAttachment = (attachment, parentKey)
                }

            case .remote:
                let (progress, _) = self.fileDownloader.data(for: attachment.key, libraryId: attachment.libraryId)
                if progress != nil {
                    self.fileDownloader.cancel(key: attachment.key, libraryId: attachment.libraryId)
                } else {
                    self.fileDownloader.download(file: file, key: attachment.key, parentKey: parentKey, libraryId: attachment.libraryId)
                }
            }
        }
    }

    private func process(downloadUpdate update: FileDownloader.Update, in viewModel: ViewModel<ItemsActionHandler>) {
        guard let parentKey = update.parentKey,
              let attachment = viewModel.state.attachments[parentKey],
              attachment.key == update.key else { return }

        var didDownloadAttachment = false

        self.update(viewModel: viewModel) { state in
            if update.kind.isDownloaded {
                var newAttachment = attachment
                // If download finished, mark attachment file location as local
                if attachment.contentType.fileLocation == .remote {
                    newAttachment = attachment.changed(location: .local)
                    state.attachments[parentKey] = newAttachment
                    didDownloadAttachment = true
                }
                state.openAttachment = (newAttachment, parentKey)
            }
            state.updateItemKey = parentKey
        }

        if didDownloadAttachment {
            self.backgroundQueue.async {
                try? self.dbStorage.createCoordinator().perform(request: MarkFileAsDownloadedDbRequest(key: attachment.key, libraryId: attachment.libraryId, downloaded: true))
            }
        }
    }

    private func cacheAttachment(for item: RItem, in viewModel: ViewModel<ItemsActionHandler>) {
        // Item has attachment, which is not cached, cache it.
        if let attachment = item.attachment {
            guard viewModel.state.attachments[item.key] == nil else { return }
            self.update(viewModel: viewModel) { state in
                state.attachments[item.key] = AttachmentCreator.attachment(for: attachment, fileStorage: self.fileStorage, urlDetector: self.urlDetector)
            }
            return
        }
        
        // Item doesn't have attachment, but there is something in cache, clear it.
        if viewModel.state.attachments[item.key] != nil {
            self.update(viewModel: viewModel) { state in
                state.attachments[item.key] = nil
            }
        }
    }

    // MARK: - Drag & Drop

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

    private func add(items itemKeys: Set<String>, to collectionKeys: Set<String>, in viewModel: ViewModel<ItemsActionHandler>) {
        let request = AssignItemsToCollectionsDbRequest(collectionKeys: collectionKeys, itemKeys: itemKeys, libraryId: viewModel.state.library.identifier)
        self.perform(request: request) { [weak viewModel] error in
            guard let viewModel = viewModel else { return }
            DDLogError("ItemsStore: can't assign collections to items - \(error)")
            self.update(viewModel: viewModel) { state in
                state.error = .collectionAssignment
            }
        }
    }

    // MARK: - Toolbar actions

    private func deleteItemsFromCollection(keys: Set<String>, in viewModel: ViewModel<ItemsActionHandler>) {
        guard let key = viewModel.state.type.collectionKey else { return }
        let request = DeleteItemsFromCollectionDbRequest(collectionKey: key, itemKeys: keys, libraryId: viewModel.state.library.identifier)
        self.perform(request: request) { [weak viewModel] error in
            guard let viewModel = viewModel else { return }
            DDLogError("ItemsStore: can't delete items - \(error)")
            self.update(viewModel: viewModel) { state in
                state.error = .deletionFromCollection
            }
        }
    }

    private func delete(items keys: Set<String>, in viewModel: ViewModel<ItemsActionHandler>) {
        let request = MarkObjectsAsDeletedDbRequest<RItem>(keys: Array(keys), libraryId: viewModel.state.library.identifier)
        self.perform(request: request) { [weak viewModel] error in
            guard let viewModel = viewModel else { return }
            DDLogError("ItemsStore: can't delete items - \(error)")
            self.update(viewModel: viewModel) { state in
                state.error = .deletion
            }
        }
    }

    private func set(trashed: Bool, to keys: Set<String>, in viewModel: ViewModel<ItemsActionHandler>) {
        let request = MarkItemsAsTrashedDbRequest(keys: Array(keys), libraryId: viewModel.state.library.identifier, trashed: trashed)
        self.perform(request: request) { [weak viewModel] error in
            guard let viewModel = viewModel else { return }
            DDLogError("ItemsStore: can't trash items - \(error)")
            self.update(viewModel: viewModel) { state in
                state.error = .deletion
            }
        }
    }

    /// Loads item which was selected for duplication from DB. When `itemDuplication` is set, appropriate screen with loaded item is opened.
    /// - parameter key: Key of item for duplication.
    private func loadItemForDuplication(key: String, in viewModel: ViewModel<ItemsActionHandler>) {
        let request = ReadItemDbRequest(libraryId: viewModel.state.library.identifier, key: key)

        do {
            let item = try self.dbStorage.createCoordinator().perform(request: request)
            self.update(viewModel: viewModel) { state in
                state.itemKeyToDuplicate = item.key
                self.stopEditing(in: &state)
            }
        } catch let error {
            DDLogError("ItemsActionHandler: could not read item - \(error)")
            self.update(viewModel: viewModel) { state in
                state.error = .duplicationLoading
            }
        }
    }

    // MARK: - Overlay actions

    private func changeSortType(to sortType: ItemsSortType, in viewModel: ViewModel<ItemsActionHandler>) {
        let results = self.results(for: viewModel.state.searchTerm, filters: viewModel.state.filters, fetchType: viewModel.state.type, sortType: sortType, libraryId: viewModel.state.library.identifier)

        self.update(viewModel: viewModel) { state in
            state.sortType = sortType
            state.results = results
            state.changes.insert(.results)
        }

        Defaults.shared.itemsSortType = sortType
    }

    private func createNote(with text: String, in viewModel: ViewModel<ItemsActionHandler>) {
        let note = Note(key: KeyGenerator.newKey, text: text)
        let request = CreateNoteDbRequest(note: note,
                                          localizedType: (self.schemaController.localized(itemType: ItemTypes.note) ?? ""),
                                          libraryId: viewModel.state.library.identifier,
                                          collectionKey: viewModel.state.type.collectionKey)
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
        let request = EditNoteDbRequest(note: note, libraryId: viewModel.state.library.identifier)
        self.perform(request: request) { [weak viewModel] error in
            guard let viewModel = viewModel else { return }
            DDLogError("ItemsStore: can't save note: \(error)")
            self.update(viewModel: viewModel) { state in
                state.error = .noteSaving
            }
        }
    }

    private func addAttachments(urls: [URL], in viewModel: ViewModel<ItemsActionHandler>) {
        let attachments = urls.map({ Files.file(from: $0) })
                              .map({
                                  Attachment(key: KeyGenerator.newKey,
                                             title: $0.name + "." + $0.ext,
                                             type: .file(file: $0, filename: ($0.name + "." + $0.ext), location: .local, linkType: .imported),
                                             libraryId: viewModel.state.library.identifier)
                              })

        do {
            try self.fileStorage.copyAttachmentFilesIfNeeded(for: attachments)

            let collections: Set<String> = viewModel.state.type.collectionKey.flatMap({ [$0] }) ?? []
            let type = self.schemaController.localized(itemType: ItemTypes.attachment) ?? ""
            let request = CreateAttachmentsDbRequest(attachments: attachments, localizedType: type, collections: collections)

            self.perform(request: request,
                         responseAction: { [weak viewModel] failedTitles in
                             guard let viewModel = viewModel else { return }
                             if !failedTitles.isEmpty {
                                 self.update(viewModel: viewModel) { state in
                                     state.error = .attachmentAdding(.someFailed(failedTitles))
                                 }
                             }
                         }, errorAction: { [weak viewModel] error in
                             guard let viewModel = viewModel else { return }
                             DDLogError("ItemsStore: can't add attachment: \(error)")
                             self.update(viewModel: viewModel) { state in
                                 state.error = .attachmentAdding(.couldNotSave)
                             }
                         })
        } catch let error {
            DDLogError("ItemsStore: can't add attachment: \(error)")
            self.update(viewModel: viewModel) { state in
                state.error = .attachmentAdding(.couldNotSave)
            }
        }
    }

    // MARK: - Searching & Filtering

    private func filter(with filters: [ItemsState.Filter], in viewModel: ViewModel<ItemsActionHandler>) {
        guard filters != viewModel.state.filters else { return }

        let results = self.results(for: viewModel.state.searchTerm, filters: filters, fetchType: viewModel.state.type, sortType: viewModel.state.sortType, libraryId: viewModel.state.library.identifier)

        self.update(viewModel: viewModel) { state in
            state.filters = filters
            state.results = results
            state.changes = [.results, .filters]
        }
    }

    private func search(for text: String?, in viewModel: ViewModel<ItemsActionHandler>) {
        guard text != viewModel.state.searchTerm else { return }

        let results = self.results(for: text, filters: viewModel.state.filters, fetchType: viewModel.state.type, sortType: viewModel.state.sortType, libraryId: viewModel.state.library.identifier)

        self.update(viewModel: viewModel) { state in
            state.searchTerm = text
            state.results = results
            state.changes = .results
        }
    }

    private func results(for searchText: String?, filters: [ItemsState.Filter], fetchType: ItemFetchType, sortType: ItemsSortType, libraryId: LibraryIdentifier) -> Results<RItem>? {
        let request = ReadItemsDbRequest(type: fetchType, libraryId: libraryId)
        guard var results = (try? self.dbStorage.createCoordinator().perform(request: request)) else { return nil }
        if let text = searchText, !text.isEmpty {
            results = results.filter(.itemSearch(for: text))
        }
        if !filters.isEmpty {
            for filter in filters {
                switch filter {
                case .downloadedFiles:
                    results = results.filter("fileDownloaded = true or mainAttachment.fileDownloaded = true")
                }
            }
        }
        return results.sorted(by: sortType.descriptors)
    }

    // MARK: - Helpers

    /// Updates the `keys` array which mirrors `Results<RItem>` identifiers. Updates `selectedItems` if needed. Updates `attachments` if needed.
    private func processUpdate(items: Results<RItem>, deletions: [Int], insertions: [Int], modifications: [Int], in viewModel: ViewModel<ItemsActionHandler>) {
        self.update(viewModel: viewModel) { state in
            if state.isEditing {
                deletions.sorted().reversed().forEach { idx in
                    let key = state.keys.remove(at: idx)
                    if state.selectedItems.remove(key) != nil {
                        state.changes.insert(.selection)
                    }
                }
            }

            modifications.forEach { idx in
                let item = items[idx]
                state.attachments[item.key] = item.attachment.flatMap({ AttachmentCreator.attachment(for: $0, fileStorage: self.fileStorage, urlDetector: self.urlDetector) })
            }

            insertions.forEach { idx in
                let item = items[idx]
                if state.isEditing {
                    state.keys.insert(item.key, at: idx)
                }
                state.attachments[item.key] = item.attachment.flatMap({ AttachmentCreator.attachment(for: $0, fileStorage: self.fileStorage, urlDetector: self.urlDetector) })
            }
        }
    }

    private func startEditing(in viewModel: ViewModel<ItemsActionHandler>) {
        var keys: [String] = []
        if let results = viewModel.state.results {
            keys = results.map({ $0.key })
        }

        self.update(viewModel: viewModel) { state in
            state.isEditing = true
            state.keys = keys
            state.changes.insert(.editing)
        }
    }

    private func stopEditing(in state: inout ItemsState) {
        state.isEditing = false
        state.keys.removeAll()
        state.selectedItems.removeAll()
        state.changes.insert(.editing)
    }

    private func perform<Request: DbResponseRequest>(request: Request, responseAction: ((Request.Response) -> Void)? = nil, errorAction: @escaping (Swift.Error) -> Void) {
        self.backgroundQueue.async {
            do {
                let response = try self.dbStorage.createCoordinator().perform(request: request)
                DispatchQueue.main.async {
                    responseAction?(response)
                }
            } catch let error {
                DispatchQueue.main.async {
                    errorAction(error)
                }
            }
        }
    }

    private func perform<Request: DbRequest>(request: Request, errorAction: @escaping (Swift.Error) -> Void) {
        self.backgroundQueue.async {
            do {
                try self.dbStorage.createCoordinator().perform(request: request)
            } catch let error {
                DispatchQueue.main.async {
                    errorAction(error)
                }
            }
        }
    }
}
