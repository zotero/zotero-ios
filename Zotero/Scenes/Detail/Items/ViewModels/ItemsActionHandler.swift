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

struct ItemsActionHandler: ViewModelActionHandler, BackgroundDbProcessingActionHandler {
    typealias State = ItemsState
    typealias Action = ItemsAction

    unowned let dbStorage: DbStorage
    private unowned let fileStorage: FileStorage
    private unowned let schemaController: SchemaController
    private unowned let urlDetector: UrlDetector
    private unowned let fileDownloader: AttachmentDownloader
    private unowned let citationController: CitationController
    private unowned let fileCleanupController: AttachmentFileCleanupController
    private unowned let syncScheduler: SynchronizationScheduler
    private unowned let htmlAttributedStringConverter: HtmlAttributedStringConverter
    let backgroundQueue: DispatchQueue
    private let disposeBag: DisposeBag
    private let quotationExpression: NSRegularExpression?

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
        self.backgroundQueue = DispatchQueue(label: "org.zotero.ItemsActionHandler.backgroundProcessing", qos: .userInitiated)
        self.dbStorage = dbStorage
        self.fileStorage = fileStorage
        self.schemaController = schemaController
        self.urlDetector = urlDetector
        self.fileDownloader = fileDownloader
        self.citationController = citationController
        self.fileCleanupController = fileCleanupController
        self.syncScheduler = syncScheduler
        self.htmlAttributedStringConverter = htmlAttributedStringConverter
        self.disposeBag = DisposeBag()

        do {
            self.quotationExpression = try NSRegularExpression(pattern: #"("[^"]+"?)"#)
        } catch let error {
            DDLogError("ItemsActionHandler: can't create quotation expression - \(error)")
            self.quotationExpression = nil
        }
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

        case .processNoteSaveResult(let result):
            processNoteSaveResult(result: result, in: viewModel)

        case .search(let text):
            self.search(for: (text.isEmpty ? nil : text), ignoreOriginal: false, in: viewModel)

        case .setSortField(let field):
            var sortType = viewModel.state.sortType
            sortType.field = field
            sortType.ascending = field.defaultOrderAscending
            self.changeSortType(to: sortType, in: viewModel)

        case .startEditing:
            self.startEditing(in: viewModel)

        case .stopEditing:
            self.update(viewModel: viewModel) { state in
                self.stopEditing(in: &state)
            }

        case .setSortOrder(let ascending):
            var sortType = viewModel.state.sortType
            sortType.ascending = ascending
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
            self.enable(filter: filter, in: viewModel)

        case .disableFilter(let filter):
            self.disable(filter: filter, in: viewModel)

        case .download(let keys):
            self.downloadAttachments(for: keys, in: viewModel)

        case .removeDownloads(let ids):
            self.fileCleanupController.delete(.allForItems(ids, viewModel.state.library.identifier), completed: nil)

        case .startSync:
            self.syncScheduler.request(sync: .ignoreIndividualDelays, libraries: .specific([viewModel.state.library.identifier]))

        case .emptyTrash:
            self.emptyTrash(in: viewModel)

        case .tagItem(let itemKey, let libraryId, let tagNames):
            self.tagItem(key: itemKey, libraryId: libraryId, with: tagNames, in: viewModel)

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

    private func tagItem(key: String, libraryId: LibraryIdentifier, with names: Set<String>, in viewModel: ViewModel<ItemsActionHandler>) {
        let request = AddTagsToItemDbRequest(key: key, libraryId: libraryId, tagNames: names)
        self.perform(request: request) { error in
            guard let error = error else { return }
            // TODO: - show error
            DDLogError("ItemsActionHandler: can't add tags - \(error)")
        }
    }

    private func emptyTrash(in viewModel: ViewModel<ItemsActionHandler>) {
        self.perform(request: EmptyTrashDbRequest(libraryId: viewModel.state.library.identifier)) { error in
            guard let error = error else { return }
            // TODO: - show error
            DDLogError("ItemsActionHandler: can't empty trash - \(error)")
        }
    }

    private func loadInitialState(in viewModel: ViewModel<ItemsActionHandler>) {
        let sortType = Defaults.shared.itemsSortType
        let results = self.results(for: viewModel.state.searchTerm, filters: viewModel.state.filters, collectionId: viewModel.state.collection.identifier, sortType: sortType, libraryId: viewModel.state.library.identifier)

        self.update(viewModel: viewModel) { state in
            state.results = results
            state.sortType = sortType
            state.error = (results == nil ? .dataLoading : nil)
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
        case .ready:
            DDLogInfo("ItemsActionHandler: download update \(attachment.key); \(attachment.libraryId); kind \(downloadUpdate.kind)")
            updateViewModel { state in
                guard let updatedAttachment = attachment.changed(location: .local) else { return }
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
        guard viewModel.state.itemAccessories[item.key] == nil, let accessory = self.accessory(for: item) else { return }
        self.update(viewModel: viewModel) { state in
            state.itemAccessories[item.key] = accessory
        }
    }

    // MARK: - Drag & Drop

    private func moveItems(from keys: Set<String>, to key: String, in viewModel: ViewModel<ItemsActionHandler>) {
        let request = MoveItemsToParentDbRequest(itemKeys: keys, parentKey: key, libraryId: viewModel.state.library.identifier)
        self.perform(request: request) { [weak viewModel] error in
            guard let viewModel = viewModel, let error = error else { return }
            DDLogError("ItemsStore: can't move items to parent: \(error)")
            self.update(viewModel: viewModel) { state in
                state.error = .itemMove
            }
        }
    }

    private func add(items itemKeys: Set<String>, to collectionKeys: Set<String>, in viewModel: ViewModel<ItemsActionHandler>) {
        let request = AssignItemsToCollectionsDbRequest(collectionKeys: collectionKeys, itemKeys: itemKeys, libraryId: viewModel.state.library.identifier)
        self.perform(request: request) { [weak viewModel] error in
            guard let viewModel = viewModel, let error = error else { return }
            DDLogError("ItemsStore: can't assign collections to items - \(error)")
            self.update(viewModel: viewModel) { state in
                state.error = .collectionAssignment
            }
        }
    }

    // MARK: - Toolbar actions

    private func deleteItemsFromCollection(keys: Set<String>, in viewModel: ViewModel<ItemsActionHandler>) {
        guard case .collection(let key) = viewModel.state.collection.identifier else { return }

        let request = DeleteItemsFromCollectionDbRequest(collectionKey: key, itemKeys: keys, libraryId: viewModel.state.library.identifier)
        self.perform(request: request) { [weak viewModel] error in
            guard let viewModel = viewModel, let error = error else { return }
            DDLogError("ItemsStore: can't delete items - \(error)")
            self.update(viewModel: viewModel) { state in
                state.error = .deletionFromCollection
            }
        }
    }

    private func delete(items keys: Set<String>, in viewModel: ViewModel<ItemsActionHandler>) {
        let request = MarkObjectsAsDeletedDbRequest<RItem>(keys: Array(keys), libraryId: viewModel.state.library.identifier)
        self.perform(request: request) { [weak viewModel] error in
            guard let viewModel = viewModel, let error = error else { return }
            DDLogError("ItemsStore: can't delete items - \(error)")
            self.update(viewModel: viewModel) { state in
                state.error = .deletion
            }
        }
    }

    private func set(trashed: Bool, to keys: Set<String>, in viewModel: ViewModel<ItemsActionHandler>) {
        let request = MarkItemsAsTrashedDbRequest(keys: Array(keys), libraryId: viewModel.state.library.identifier, trashed: trashed)
        self.perform(request: request) { [weak viewModel] error in
            guard let viewModel = viewModel, let error = error else { return }
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

    // MARK: - Overlay actions

    private func changeSortType(to sortType: ItemsSortType, in viewModel: ViewModel<ItemsActionHandler>) {
        let results = self.results(for: viewModel.state.searchTerm, filters: viewModel.state.filters, collectionId: viewModel.state.collection.identifier, sortType: sortType, libraryId: viewModel.state.library.identifier)

        self.update(viewModel: viewModel) { state in
            state.sortType = sortType
            state.results = results
            state.changes.insert(.results)
        }

        Defaults.shared.itemsSortType = sortType
    }

    private func processNoteSaveResult(result: NoteEditorSaveResult, in viewModel: ViewModel<ItemsActionHandler>) {
        switch result {
        case .success:
            break

        case .failure(let error):
            DispatchQueue.main.async { [weak viewModel] in
                DDLogError("ItemsStore: can't save note: \(error)")
                guard let viewModel else { return }
                update(viewModel: viewModel) { state in
                    state.error = .noteSaving
                }
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

        self.perform(request: request, invalidateRealm: true) { [weak viewModel] result in
            guard let viewModel = viewModel else { return }

            switch result {
            case .success(let failed):
                guard !failed.isEmpty else { return }
                self.update(viewModel: viewModel) { state in
                    state.error = .attachmentAdding(.someFailed(failed.map({ $0.1 })))
                }

            case .failure(let error):
                DDLogError("ItemsActionHandler: can't add attachment: \(error)")
                self.update(viewModel: viewModel) { state in
                    state.error = .attachmentAdding(.couldNotSave)
                }
            }
        }
    }

    // MARK: - Searching & Filtering

    private func enable(filter: ItemsFilter, in viewModel: ViewModel<ItemsActionHandler>) {
        var filters = viewModel.state.filters

        guard !filters.contains(filter) else { return }

        let modificationIndex = filters.firstIndex(where: { existing in
            switch (existing, filter) {
            // Update array inside existing `tags` filter
            case (.tags, .tags): return true
            default: return false
            }
        })

        if let index = modificationIndex {
            filters[index] = filter
        } else {
            filters.append(filter)
        }

        self.filter(with: filters, in: viewModel)
    }

    private func disable(filter: ItemsFilter, in viewModel: ViewModel<ItemsActionHandler>) {
        var filters = viewModel.state.filters

        guard let index = filters.firstIndex(of: filter) else { return }

        filters.remove(at: index)
        self.filter(with: filters, in: viewModel)
    }

    private func filter(with filters: [ItemsFilter], in viewModel: ViewModel<ItemsActionHandler>) {
        guard filters != viewModel.state.filters else { return }

        let results = self.results(for: viewModel.state.searchTerm, filters: filters, collectionId: viewModel.state.collection.identifier, sortType: viewModel.state.sortType, libraryId: viewModel.state.library.identifier)

        self.update(viewModel: viewModel) { state in
            state.filters = filters
            state.results = results
            state.changes = [.results, .filters]
        }
    }

    private func search(for text: String?, ignoreOriginal: Bool, in viewModel: ViewModel<ItemsActionHandler>) {
        guard ignoreOriginal || text != viewModel.state.searchTerm else { return }

        let results = self.results(for: text, filters: viewModel.state.filters, collectionId: viewModel.state.collection.identifier, sortType: viewModel.state.sortType, libraryId: viewModel.state.library.identifier)

        self.update(viewModel: viewModel) { state in
            state.searchTerm = text
            state.results = results
            state.changes = .results
        }
    }

    private func results(for searchText: String?, filters: [ItemsFilter], collectionId: CollectionIdentifier, sortType: ItemsSortType, libraryId: LibraryIdentifier) -> Results<RItem>? {
        var searchComponents: [String] = []
        if let text = searchText, !text.isEmpty {
            searchComponents = self.createComponents(from: text)
        }
        let request = ReadItemsDbRequest(collectionId: collectionId, libraryId: libraryId, filters: filters, sortType: sortType, searchTextComponents: searchComponents)
        return try? self.dbStorage.perform(request: request, on: .main)
    }

    private func createComponents(from searchTerm: String) -> [String] {
        guard let expression = self.quotationExpression else { return [searchTerm] }

        let normalizedSearchTerm = searchTerm.replacingOccurrences(of: #"“"#, with: "\"")
                                             .replacingOccurrences(of: #"”"#, with: "\"")

        let matches = expression.matches(in: normalizedSearchTerm, options: [], range: NSRange(normalizedSearchTerm.startIndex..., in: normalizedSearchTerm))

        guard !matches.isEmpty else {
            return self.separateComponents(from: normalizedSearchTerm)
        }

        var components: [String] = []
        for (idx, match) in matches.enumerated() {
            if match.range.lowerBound > 0 {
                let lowerBound = idx == 0 ? 0 : matches[idx - 1].range.upperBound
                let precedingRange = normalizedSearchTerm.index(normalizedSearchTerm.startIndex, offsetBy: lowerBound)..<normalizedSearchTerm.index(normalizedSearchTerm.startIndex, offsetBy: match.range.lowerBound)
                let precedingComponents = self.separateComponents(from: String(normalizedSearchTerm[precedingRange]))
                components.append(contentsOf: precedingComponents)
            }

            let upperBound = normalizedSearchTerm[normalizedSearchTerm.index(normalizedSearchTerm.startIndex, offsetBy: (match.range.upperBound - 1))] == "\"" ? match.range.upperBound - 1 : match.range.upperBound
            let range = normalizedSearchTerm.index(normalizedSearchTerm.startIndex, offsetBy: (match.range.lowerBound + 1))..<normalizedSearchTerm.index(normalizedSearchTerm.startIndex, offsetBy: upperBound)
            components.append(String(normalizedSearchTerm[range]))
        }

        if let match = matches.last, match.range.upperBound != (normalizedSearchTerm.count - 1) {
            let lastRange = normalizedSearchTerm.index(normalizedSearchTerm.startIndex, offsetBy: match.range.upperBound)..<normalizedSearchTerm.endIndex
            let lastComponents = self.separateComponents(from: String(normalizedSearchTerm[lastRange]))
            components.append(contentsOf: lastComponents)
        }

        return components
    }

    private func separateComponents(from string: String) -> [String] {
        return string.components(separatedBy: " ").filter({ !$0.isEmpty })
    }

    // MARK: - Helpers

    private func accessory(for item: RItem) -> ItemAccessory? {
        if let attachment = AttachmentCreator.mainAttachment(for: item, fileStorage: self.fileStorage) {
            return .attachment(attachment: attachment, parentKey: item.key)
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
                    state.itemAccessories[key] = nil
                    state.itemTitles[key] = nil
                }
            }

            modifications.forEach { idx in
                let item = items[idx]
                state.itemAccessories[item.key] = self.accessory(for: item)
                state.itemTitles[item.key] = self.htmlAttributedStringConverter.convert(text: item.displayTitle, baseAttributes: [.font: state.itemTitleFont])
            }

            insertions.forEach { idx in
                let item = items[idx]
                if state.isEditing {
                    state.keys.insert(item.key, at: idx)
                }
                state.itemAccessories[item.key] = self.accessory(for: item)
                state.itemTitles[item.key] = self.htmlAttributedStringConverter.convert(text: item.displayTitle, baseAttributes: [.font: state.itemTitleFont])
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
