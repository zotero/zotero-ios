//
//  ItemsActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 21/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift
import RealmSwift
import RxSwift

struct ItemsActionHandler: ViewModelActionHandler {
    typealias State = ItemsState
    typealias Action = ItemsAction

    private unowned let dbStorage: DbStorage
    private unowned let fileStorage: FileStorage
    private unowned let schemaController: SchemaController
    private unowned let urlDetector: UrlDetector
    private unowned let backgroundQueue: DispatchQueue
    private unowned let fileDownloader: AttachmentDownloader
    private unowned let citationController: CitationController
    private let disposeBag: DisposeBag

    init(dbStorage: DbStorage, fileStorage: FileStorage, schemaController: SchemaController, urlDetector: UrlDetector, fileDownloader: AttachmentDownloader, citationController: CitationController) {
        self.backgroundQueue = DispatchQueue.global(qos: .userInitiated)
        self.dbStorage = dbStorage
        self.fileStorage = fileStorage
        self.schemaController = schemaController
        self.urlDetector = urlDetector
        self.fileDownloader = fileDownloader
        self.citationController = citationController
        self.disposeBag = DisposeBag()
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

        case .saveNote(let key, let text, let tags):
            self.saveNote(text: text, tags: tags, key: key, in: viewModel)

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

        case .cacheItemAccessory(let item):
            self.cacheItemAccessory(for: item, in: viewModel)

        case .updateKeys(let items, let deletions, let insertions, let modifications):
            self.processUpdate(items: items, deletions: deletions, insertions: insertions, modifications: modifications, in: viewModel)

        case .updateDownload(let update):
            self.process(downloadUpdate: update, in: viewModel)

        case .openAttachment(let attachment, let parentKey):
            self.process(attachment: attachment, parentKey: parentKey)

        case .updateAttachments(let notification):
            self.updateDeletedAttachments(notification, in: viewModel)

        case .filter(let filters):
            self.filter(with: filters, in: viewModel)

        case .quickCopyBibliography(let item, let controller):
            self.citationController.bibliography(for: item, styleId: Defaults.shared.exportDefaultStyleId, localeId: Defaults.shared.exportDefaultLocaleId, format: .html, in: controller)
                                   .subscribe(onSuccess: { citation in
                                       UIPasteboard.general.string = citation
                                    // TODO: - show something
                                   }, onFailure: { error in
                                    // TODO: Show something
                                   })
                                   .disposed(by: self.disposeBag)
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
        switch notification {
        case .all:
            // Update all attachment locations to `.remote`.
            self.update(viewModel: viewModel) { state in
                self.changeAttachmentsToRemoteLocation(in: &state.itemAccessories)
                state.changes = .attachmentsRemoved
            }

        case .library(let libraryId):
            // Check whether files in this library have been deleted.
            guard viewModel.state.library.identifier == libraryId else { return }
            // Update all attachment locations to `.remote`.
            self.update(viewModel: viewModel) { state in
                self.changeAttachmentsToRemoteLocation(in: &state.itemAccessories)
                state.changes = .attachmentsRemoved
            }

        case .individual(let key, let parentKey, let libraryId):
            let updateKey = parentKey ?? key

            // Check whether the deleted file was in this library and there is a cached accessory for it.
            guard viewModel.state.library.identifier == libraryId,
                  let accessory = viewModel.state.itemAccessories[updateKey],
                  let updatedAccessory = accessory.updatedAttachment(update: { attachment in attachment.changed(location: .remote, condition: { $0 == .local }) }) else { return }
            self.update(viewModel: viewModel) { state in
                state.itemAccessories[updateKey] = updatedAccessory
                state.updateItemKey = updateKey
            }
        }
    }

    private func changeAttachmentsToRemoteLocation(in accessories: inout [String: ItemAccessory]) {
        for (key, accessory) in accessories {
            guard let updatedAccessory = accessory.updatedAttachment(update: { attachment in attachment.changed(location: .remote, condition: { $0 == .local }) }) else { continue }
            accessories[key] = updatedAccessory
        }
    }

    private func process(attachment: Attachment, parentKey: String?) {
        let (progress, _) = self.fileDownloader.data(for: attachment.key, libraryId: attachment.libraryId)
        if progress != nil {
            self.fileDownloader.cancel(key: attachment.key, libraryId: attachment.libraryId)
        } else {
            self.fileDownloader.download(attachment: attachment, parentKey: parentKey)
        }
    }

    private func process(downloadUpdate update: AttachmentDownloader.Update, in viewModel: ViewModel<ItemsActionHandler>) {
        let updateKey = update.parentKey ?? update.key
        guard let accessory = viewModel.state.itemAccessories[updateKey], let attachment = accessory.attachment else { return }

        switch update.kind {
        case .ready:
            guard let updatedAttachment = attachment.changed(location: .local) else { return }
            self.update(viewModel: viewModel) { state in
                state.itemAccessories[updateKey] = .attachment(updatedAttachment)
                state.updateItemKey = updateKey
            }

        case .cancelled, .failed, .progress:
            self.update(viewModel: viewModel) { state in
                state.updateItemKey = updateKey
            }
        }
    }

    private func cacheItemAccessory(for item: RItem, in viewModel: ViewModel<ItemsActionHandler>) {
        // Create cached accessory only if there is nothing in cache yet.
        guard viewModel.state.itemAccessories[item.key] == nil, let accessory = self.accessory(for: item) else { return }
        self.update(viewModel: viewModel) { state in
            state.itemAccessories[item.key] = accessory
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

    private func saveNote(text: String, tags: [Tag], key: String, in viewModel: ViewModel<ItemsActionHandler>) {
        let note = Note(key: key, text: text, tags: tags)
        let libraryId = viewModel.state.library.identifier
        let collectionKey = viewModel.state.type.collectionKey

        let handleError: (Error) -> Void = { [weak viewModel] error in
            DispatchQueue.main.async {
                DDLogError("ItemsStore: can't save note: \(error)")
                guard let viewModel = viewModel else { return }
                self.update(viewModel: viewModel) { state in
                    state.error = .noteSaving
                }
            }
        }

        self.backgroundQueue.async {
            do {
                try self.dbStorage.createCoordinator().perform(request: EditNoteDbRequest(note: note, libraryId: libraryId))
            } catch let error as DbError where error.isObjectNotFound {
                do {
                    let request = CreateNoteDbRequest(note: note, localizedType: (self.schemaController.localized(itemType: ItemTypes.note) ?? ""), libraryId: libraryId, collectionKey: collectionKey)
                    _ = try self.dbStorage.createCoordinator().perform(request: request)
                } catch let error {
                    handleError(error)
                }
            } catch let error {
                handleError(error)
            }
        }
    }

    private func addAttachments(urls: [URL], in viewModel: ViewModel<ItemsActionHandler>) {
        let libraryId = viewModel.state.library.identifier
        var attachments: [Attachment] = []

        for url in urls {
            let key = KeyGenerator.newKey
            let original = Files.file(from: url)
            let filename = (original.name + "." + original.ext)
            let file = Files.attachmentFile(in: libraryId, key: key, filename: filename, contentType: original.mimeType)

            do {
                try self.fileStorage.move(from: original, to: file)
            } catch let error {
                DDLogError("ItemsActionHandler: can't move file from \(error)")
                continue
            }

            attachments.append(Attachment(type: .file(filename: filename, contentType: original.mimeType, location: .local, linkType: .importedFile),
                                          title: filename,
                                          key: key,
                                          libraryId: libraryId))
        }

        if attachments.isEmpty {
            self.update(viewModel: viewModel) { state in
                state.error = .attachmentAdding(.couldNotSave)
            }
            return
        }

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
                    results = results.filter("fileDownloaded = true or ANY children.fileDownloaded = true")
                }
            }
        }
        return results.sorted(by: sortType.descriptors)
    }

    // MARK: - Helpers

    private func accessory(for item: RItem) -> ItemAccessory? {
        if let attachment = AttachmentCreator.mainAttachment(for: item, fileStorage: self.fileStorage) {
            return .attachment(attachment)
        }

        if let urlString = item.urlString, self.urlDetector.isUrl(string: urlString), let url = URL(string: urlString) {
            return .url(url)
        }

        if let doi = item.doi {
            return .doi(doi)
        }

        return nil
    }

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
                state.itemAccessories[item.key] = self.accessory(for: item)
            }

            insertions.forEach { idx in
                let item = items[idx]
                if state.isEditing {
                    state.keys.insert(item.key, at: idx)
                }
                state.itemAccessories[item.key] = self.accessory(for: item)
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
