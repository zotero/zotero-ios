//
//  ItemsActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 21/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import MobileCoreServices
import WebKit

import CocoaLumberjackSwift
import RealmSwift
import RxSwift

final class ItemsActionHandler: BaseItemsActionHandler, ViewModelActionHandler {
    typealias State = ItemsState
    typealias Action = ItemsAction

    private unowned let fileStorage: FileStorage
    private unowned let schemaController: SchemaController
    private unowned let urlDetector: UrlDetector
    private unowned let fileDownloader: AttachmentDownloader
    private unowned let citationController: CitationController
    private unowned let fileCleanupController: AttachmentFileCleanupController
    private unowned let syncScheduler: SynchronizationScheduler
    private unowned let htmlAttributedStringConverter: HtmlAttributedStringConverter
    private let disposeBag: DisposeBag

    init(
        dbStorage: DbStorage,
        fileStorage: FileStorage,
        schemaController: SchemaController,
        urlDetector: UrlDetector,
        fileDownloader: AttachmentDownloader,
        citationController: CitationController,
        fileCleanupController: AttachmentFileCleanupController,
        syncScheduler: SynchronizationScheduler,
        htmlAttributedStringConverter: HtmlAttributedStringConverter
    ) {
        self.fileStorage = fileStorage
        self.schemaController = schemaController
        self.urlDetector = urlDetector
        self.fileDownloader = fileDownloader
        self.citationController = citationController
        self.fileCleanupController = fileCleanupController
        self.syncScheduler = syncScheduler
        self.htmlAttributedStringConverter = htmlAttributedStringConverter
        self.disposeBag = DisposeBag()
        super.init(dbStorage: dbStorage)
    }

    func process(action: ItemsAction, in viewModel: ViewModel<ItemsActionHandler>) {
        let handleBaseActionResult: (Result<Void, ItemsError>) -> Void = { [weak self, weak viewModel] result in
            guard let self, let viewModel else { return }
            switch result {
            case .failure(let error):
                update(viewModel: viewModel) { state in
                    state.error = error
                }

            case .success:
                break
            }
        }

        switch action {
        case .addAttachments(let urls):
            self.addAttachments(urls: urls, in: viewModel)

        case .assignItemsToCollections(let items, let collections):
            add(items: items, to: collections, libraryId: viewModel.state.library.identifier, completion: handleBaseActionResult)

        case .deleteItemsFromCollection(let keys):
            deleteItemsFromCollection(keys: keys, collectionId: viewModel.state.collection.identifier, libraryId: viewModel.state.library.identifier, completion: handleBaseActionResult)

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
            moveItems(from: fromKeys, to: toKey, libraryId: viewModel.state.library.identifier, completion: handleBaseActionResult)

        case .observingFailed:
            self.update(viewModel: viewModel) { state in
                state.error = .dataLoading
            }

        case .search(let text):
            self.search(for: (text.isEmpty ? nil : text), ignoreOriginal: false, in: viewModel)

        case .setSortType(let type):
            changeSortType(to: type, in: viewModel)

        case .startEditing:
            self.startEditing(in: viewModel)

        case .stopEditing:
            self.update(viewModel: viewModel) { state in
                self.stopEditing(in: &state)
            }

        case .trashItems(let keys):
            set(trashed: true, to: keys, libraryId: viewModel.state.library.identifier, completion: handleBaseActionResult)

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

        case .updateDownload(let update, let batchData):
            self.process(downloadUpdate: update, batchData: batchData, in: viewModel)

        case .updateIdentifierLookup(let update, let batchData):
            self.process(identifierLookupUpdate: update, batchData: batchData, in: viewModel)

        case .updateRemoteDownload(let update, let batchData):
            self.process(remoteDownloadUpdate: update, batchData: batchData, in: viewModel)

        case .openAttachment(let attachment, let parentKey):
            self.open(attachment: attachment, parentKey: parentKey, in: viewModel)

        case .attachmentOpened(let key):
            guard viewModel.state.attachmentToOpen == key else { return }
            self.update(viewModel: viewModel) { state in
                state.attachmentToOpen = nil
            }

        case .updateAttachments(let notification):
            self.updateDeletedAttachments(notification, in: viewModel)

        case .enableFilter(let filter):
            self.filter(with: add(filter: filter, to: viewModel.state.filters), in: viewModel)

        case .disableFilter(let filter):
            self.filter(with: remove(filter: filter, from: viewModel.state.filters), in: viewModel)

        case .download(let keys):
            self.downloadAttachments(for: keys, in: viewModel)

        case .removeDownloads(let ids):
            self.fileCleanupController.delete(.allForItems(ids, viewModel.state.library.identifier))

        case .tagItem(let itemKey, let libraryId, let tagNames):
            tagItem(key: itemKey, libraryId: libraryId, with: tagNames)

        case .cacheItemTitle(let key, let title):
            self.update(viewModel: viewModel) { state in
                state.itemTitles[key] = self.htmlAttributedStringConverter.convert(text: title, baseAttributes: [.font: state.itemTitleFont])
            }

        case .clearTitleCache:
            self.update(viewModel: viewModel) { state in
                state.itemTitles = [:]
            }
        }
    }

    private func loadInitialState(in viewModel: ViewModel<ItemsActionHandler>) {
        do {
            let (library, libraryToken) = try viewModel.state.library.identifier.observe(in: dbStorage, changes: { [weak self, weak viewModel] library in
                guard let self, let viewModel else { return }
                update(viewModel: viewModel) { state in
                    state.library = library
                    state.changes = .library
                }
            })
            let results = try results(
                for: viewModel.state.searchTerm,
                filters: viewModel.state.filters,
                collectionId: viewModel.state.collection.identifier,
                sortType: viewModel.state.sortType,
                libraryId: viewModel.state.library.identifier
            )

            update(viewModel: viewModel) { state in
                state.results = results
                state.library = library
                state.libraryToken = libraryToken
            }
        } catch let error {
            update(viewModel: viewModel) { state in
                state.error = (error as? ItemsError) ?? .dataLoading
            }
        }
    }

    // MARK: - Attachments

    private func downloadAttachments(for keys: Set<String>, in viewModel: ViewModel<ItemsActionHandler>) {
        var attachments: [(Attachment, String?)] = []
        for key in keys {
            guard let attachment = viewModel.state.itemAccessories[key]?.attachment else { continue }
            let parentKey = attachment.key == key ? nil : key
            attachments.append((attachment, parentKey))
        }
        fileDownloader.batchDownload(attachments: attachments)
    }

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

        case .allForItems(let keys, let libraryId):
            // Check whether files in this library have been deleted.
            guard viewModel.state.library.identifier == libraryId else { return }

            self.update(viewModel: viewModel) { state in
                for key in keys {
                    guard let accessory = viewModel.state.itemAccessories[key],
                          let updatedAccessory = accessory.updatedAttachment(update: { attachment in attachment.changed(location: .remote, condition: { $0 == .local }) }) else { continue }
                    state.itemAccessories[key] = updatedAccessory
                }
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

    private func open(attachment: Attachment, parentKey: String?, in viewModel: ViewModel<ItemsActionHandler>) {
        let (progress, _) = self.fileDownloader.data(for: attachment.key, parentKey: parentKey, libraryId: attachment.libraryId)
        if progress != nil {
            if viewModel.state.attachmentToOpen == attachment.key {
                self.update(viewModel: viewModel) { state in
                    state.attachmentToOpen = nil
                }
            }

            self.fileDownloader.cancel(key: attachment.key, parentKey: parentKey, libraryId: attachment.libraryId)
        } else {
            self.update(viewModel: viewModel) { state in
                state.attachmentToOpen = attachment.key
            }

            self.fileDownloader.downloadIfNeeded(attachment: attachment, parentKey: parentKey)
        }
    }

    private func process(downloadUpdate: AttachmentDownloader.Update, batchData: ItemsState.DownloadBatchData?, in viewModel: ViewModel<ItemsActionHandler>) {
        let updateKey = downloadUpdate.parentKey ?? downloadUpdate.key
        guard let accessory = viewModel.state.itemAccessories[updateKey], let attachment = accessory.attachment else {
            updateViewModel()
            return
        }

        switch downloadUpdate.kind {
        case .ready(let compressed):
            DDLogInfo("ItemsActionHandler: download update \(attachment.key); \(attachment.libraryId); kind \(downloadUpdate.kind)")
            guard let updatedAttachment = attachment.changed(location: .local, compressed: compressed) else { return }
            updateViewModel { state in
                state.itemAccessories[updateKey] = .attachment(attachment: updatedAttachment, parentKey: downloadUpdate.parentKey)
                state.updateItemKey = updateKey
            }

        case .progress:
            // If file is being extracted, the extraction is usually very quick and sends multiple quick progress updates, due to switching between queues and small delays those updates are then
            // received here, but the file downloader is already done and we're unnecessarily reloading the table view with the same progress. So we're filtering out those unnecessary updates
            guard let currentProgress = fileDownloader.data(for: downloadUpdate.key, parentKey: downloadUpdate.parentKey, libraryId: downloadUpdate.libraryId).progress, currentProgress < 1
            else { return }
            updateViewModel { state in
                state.updateItemKey = updateKey
            }

        case .cancelled, .failed:
            DDLogInfo("ItemsActionHandler: download update \(attachment.key); \(attachment.libraryId); kind \(downloadUpdate.kind)")
            updateViewModel { state in
                state.updateItemKey = updateKey
            }
        }

        func updateViewModel(additional: ((inout ItemsState) -> Void)? = nil) {
            update(viewModel: viewModel) { state in
                if state.downloadBatchData != batchData {
                    state.downloadBatchData = batchData
                    state.changes = .batchData
                }

                additional?(&state)
            }
        }
    }
    
    private func process(identifierLookupUpdate update: IdentifierLookupController.Update, batchData: ItemsState.IdentifierLookupBatchData, in viewModel: ViewModel<ItemsActionHandler>) {
        self.update(viewModel: viewModel) { state in
            if state.identifierLookupBatchData != batchData {
                state.identifierLookupBatchData = batchData
                state.changes = .batchData
            }
        }
    }
    
    private func process(remoteDownloadUpdate update: RemoteAttachmentDownloader.Update, batchData: ItemsState.DownloadBatchData?, in viewModel: ViewModel<ItemsActionHandler>) {
        self.update(viewModel: viewModel) { state in
            if state.remoteDownloadBatchData != batchData {
                state.remoteDownloadBatchData = batchData
                state.changes = .batchData
            }
        }
    }

    private func cacheItemAccessory(for item: RItem, in viewModel: ViewModel<ItemsActionHandler>) {
        // Create cached accessory only if there is nothing in cache yet.
        guard viewModel.state.itemAccessories[item.key] == nil, let accessory = ItemAccessory.create(from: item, fileStorage: fileStorage, urlDetector: urlDetector) else { return }
        self.update(viewModel: viewModel) { state in
            state.itemAccessories[item.key] = accessory
        }
    }

    // MARK: - Drag & Drop

    private func moveItems(from keys: Set<String>, to key: String, libraryId: LibraryIdentifier, completion: @escaping (Result<Void, ItemsError>) -> Void) {
        let request = MoveItemsToParentDbRequest(itemKeys: keys, parentKey: key, libraryId: libraryId)
        perform(request: request) { error in
            guard let error else { return }
            DDLogError("BaseItemsActionHandler: can't move items to parent: \(error)")
            completion(.failure(.itemMove))
        }
    }

    private func add(items itemKeys: Set<String>, to collectionKeys: Set<String>, libraryId: LibraryIdentifier, completion: @escaping (Result<Void, ItemsError>) -> Void) {
        let request = AssignItemsToCollectionsDbRequest(collectionKeys: collectionKeys, itemKeys: itemKeys, libraryId: libraryId)
        perform(request: request) { error in
            guard let error else { return }
            DDLogError("BaseItemsActionHandler: can't assign collections to items - \(error)")
            completion(.failure(.collectionAssignment))
        }
    }

    // MARK: - Toolbar actions

    /// Loads item which was selected for duplication from DB. When `itemDuplication` is set, appropriate screen with loaded item is opened.
    /// - parameter key: Key of item for duplication.
    private func loadItemForDuplication(key: String, in viewModel: ViewModel<ItemsActionHandler>) {
        let request = ReadItemDbRequest(libraryId: viewModel.state.library.identifier, key: key)

        do {
            let item = try self.dbStorage.perform(request: request, on: .main)
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

    private func deleteItemsFromCollection(keys: Set<String>, collectionId: CollectionIdentifier, libraryId: LibraryIdentifier, completion: @escaping (Result<Void, ItemsError>) -> Void) {
        guard let key = collectionId.key else { return }
        let request = DeleteItemsFromCollectionDbRequest(collectionKey: key, itemKeys: keys, libraryId: libraryId)
        perform(request: request) { error in
            guard let error else { return }
            DDLogError("BaseItemsActionHandler: can't delete items - \(error)")
            completion(.failure(.deletionFromCollection))
        }
    }

    private func set(trashed: Bool, to keys: Set<String>, libraryId: LibraryIdentifier, completion: @escaping (Result<Void, ItemsError>) -> Void) {
        let request = MarkItemsAsTrashedDbRequest(keys: Array(keys), libraryId: libraryId, trashed: trashed)
        perform(request: request) { error in
            guard let error else { return }
            DDLogError("BaseItemsActionHandler: can't trash items - \(error)")
            completion(.failure(.deletion))
        }
    }

    // MARK: - Overlay actions

    private func changeSortType(to sortType: ItemsSortType, in viewModel: ViewModel<ItemsActionHandler>) {
        guard sortType != viewModel.state.sortType else { return }

        let results = try? results(
            for: viewModel.state.searchTerm,
            filters: viewModel.state.filters,
            collectionId: viewModel.state.collection.identifier,
            sortType: sortType,
            libraryId: viewModel.state.library.identifier
        )

        update(viewModel: viewModel) { state in
            state.sortType = sortType
            state.results = results
            state.changes.insert(.results)
        }

        Defaults.shared.itemsSortType = sortType
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
                DDLogError("ItemsActionHandler: can't move file - \(error)")
                continue
            }

            attachments.append(
                Attachment(
                    type: .file(filename: filename, contentType: original.mimeType, location: .local, linkType: .importedFile, compressed: false),
                    title: filename,
                    key: key,
                    libraryId: libraryId
                )
            )
        }

        if attachments.isEmpty {
            self.update(viewModel: viewModel) { state in
                state.error = .attachmentAdding(.couldNotSave)
            }
            return
        }

        let collections: Set<String>
        switch viewModel.state.collection.identifier {
        case .collection(let key):
            collections = [key]

        case .search, .custom:
            collections = []
        }

        let type = self.schemaController.localized(itemType: ItemTypes.attachment) ?? ""
        let request = CreateAttachmentsDbRequest(attachments: attachments, parentKey: nil, localizedType: type, collections: collections)

        self.perform(request: request, invalidateRealm: true) { [weak self, weak viewModel] result in
            guard let self, let viewModel else { return }

            switch result {
            case .success(let failed):
                guard !failed.isEmpty else { return }
                update(viewModel: viewModel) { state in
                    state.error = .attachmentAdding(.someFailed(failed.map({ $0.1 })))
                }

            case .failure(let error):
                DDLogError("ItemsActionHandler: can't add attachment: \(error)")
                update(viewModel: viewModel) { state in
                    state.error = .attachmentAdding(.couldNotSave)
                }
            }
        }
    }

    // MARK: - Searching & Filtering

    private func filter(with filters: [ItemsFilter], in viewModel: ViewModel<ItemsActionHandler>) {
        guard filters != viewModel.state.filters else { return }

        let results = try? results(
            for: viewModel.state.searchTerm,
            filters: filters,
            collectionId: viewModel.state.collection.identifier,
            sortType: viewModel.state.sortType,
            libraryId: viewModel.state.library.identifier
        )
        update(viewModel: viewModel) { state in
            state.filters = filters
            state.results = results
            state.changes = [.results, .filters]
        }
    }

    private func search(for text: String?, ignoreOriginal: Bool, in viewModel: ViewModel<ItemsActionHandler>) {
        guard ignoreOriginal || text != viewModel.state.searchTerm else { return }

        let results = try? results(
            for: text,
            filters: viewModel.state.filters,
            collectionId: viewModel.state.collection.identifier,
            sortType: viewModel.state.sortType,
            libraryId: viewModel.state.library.identifier
        )
        update(viewModel: viewModel) { state in
            state.searchTerm = text
            state.results = results
            state.changes = .results
        }
    }

    private func results(for searchText: String?, filters: [ItemsFilter], collectionId: CollectionIdentifier, sortType: ItemsSortType, libraryId: LibraryIdentifier) throws -> Results<RItem> {
        var searchComponents: [String] = []
        if let text = searchText, !text.isEmpty {
            searchComponents = createComponents(from: text)
        }
        let request = ReadItemsDbRequest(collectionId: collectionId, libraryId: libraryId, filters: filters, sortType: sortType, searchTextComponents: searchComponents)
        return try self.dbStorage.perform(request: request, on: .main)
    }

    // MARK: - Helpers

    /// Updates the `keys` array which mirrors `Results<RItem>` identifiers. Updates `selectedItems` if needed. Updates `attachments` if needed.
    private func processUpdate(items: Results<RItem>, deletions: [Int], insertions: [Int], modifications: [Int], in viewModel: ViewModel<ItemsActionHandler>) {
        self.update(viewModel: viewModel) { state in
            var shouldRebuildKeys = false

            for idx in deletions.sorted().reversed() {
                guard idx < state.keys.count else {
                    shouldRebuildKeys = true
                    state.selectedItems = []
                    state.changes.insert(.selection)
                    break
                }
                let key = state.keys.remove(at: idx)
                if state.selectedItems.remove(key) != nil {
                    state.changes.insert(.selection)
                }
                state.itemAccessories[key] = nil
                state.itemTitles[key] = nil
            }

            modifications.forEach { idx in
                let item = items[idx]
                state.itemAccessories[item.key] = ItemAccessory.create(from: item, fileStorage: fileStorage, urlDetector: urlDetector)
                state.itemTitles[item.key] = self.htmlAttributedStringConverter.convert(text: item.displayTitle, baseAttributes: [.font: state.itemTitleFont])
            }

            for idx in insertions {
                let item = items[idx]
                state.itemAccessories[item.key] = ItemAccessory.create(from: item, fileStorage: fileStorage, urlDetector: urlDetector)
                state.itemTitles[item.key] = self.htmlAttributedStringConverter.convert(text: item.displayTitle, baseAttributes: [.font: state.itemTitleFont])

                if !shouldRebuildKeys {
                    if idx >= state.keys.count {
                        shouldRebuildKeys = true
                        continue
                    }
                    state.keys.insert(item.key, at: idx)
                }
            }

            if shouldRebuildKeys {
                state.keys = Array(items.map({ $0.key }))
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
}
