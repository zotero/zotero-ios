//
//  TrashActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 18.07.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import OrderedCollections

import CocoaLumberjackSwift
import RealmSwift
import RxSwift

final class TrashActionHandler: BaseItemsActionHandler, ViewModelActionHandler {
    typealias State = TrashState
    typealias Action = TrashAction

    private unowned let schemaController: SchemaController
    private unowned let fileStorage: FileStorage
    private unowned let fileDownloader: AttachmentDownloader
    private unowned let urlDetector: UrlDetector
    private unowned let htmlAttributedStringConverter: HtmlAttributedStringConverter
    private unowned let fileCleanupController: AttachmentFileCleanupController
    private let disposeBag: DisposeBag

    init(
        dbStorage: DbStorage,
        schemaController: SchemaController,
        fileStorage: FileStorage,
        fileDownloader: AttachmentDownloader,
        urlDetector: UrlDetector,
        htmlAttributedStringConverter: HtmlAttributedStringConverter,
        fileCleanupController: AttachmentFileCleanupController
    ) {
        self.schemaController = schemaController
        self.fileStorage = fileStorage
        self.fileDownloader = fileDownloader
        self.urlDetector = urlDetector
        self.htmlAttributedStringConverter = htmlAttributedStringConverter
        self.fileCleanupController = fileCleanupController
        disposeBag = DisposeBag()
        super.init(dbStorage: dbStorage)
    }

    func process(action: TrashAction, in viewModel: ViewModel<TrashActionHandler>) {
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
        case .loadData:
            loadData(in: viewModel)

        case .deleteObjects(let keys):
            delete(objects: keys, viewModel: viewModel)

        case .download(let keys):
            downloadAttachments(for: keys, in: viewModel)

        case .removeDownloads(let keys):
            var items: Set<String> = []
            for key in keys {
                guard key.type == .item else { continue }
                items.insert(key.key)
            }
            fileCleanupController.delete(.allForItems(items, viewModel.state.library.identifier))

        case .emptyTrash:
            emptyTrash(in: viewModel)

        case .tagItem(let itemKey, let libraryId, let tagNames):
            tagItem(key: itemKey, libraryId: libraryId, with: tagNames)

        case .restoreItems(let keys):
            set(trashed: false, to: keys, libraryId: viewModel.state.library.identifier, completion: handleBaseActionResult)

        case .startEditing:
            startEditing(in: viewModel)

        case .stopEditing:
            stopEditing(in: viewModel)

        case .enableFilter(let filter):
            self.filter(with: add(filter: filter, to: viewModel.state.filters), in: viewModel)

        case .disableFilter(let filter):
            self.filter(with: remove(filter: filter, from: viewModel.state.filters), in: viewModel)

        case .search(let term):
            search(with: term, in: viewModel)

        case .setSortType(let type):
            changeSortType(to: type, in: viewModel)

        case .toggleSelectionState:
            update(viewModel: viewModel) { state in
                if state.selectedItems.count != state.snapshot.count {
                    state.selectedItems = Set(state.snapshot.sortedKeys)
                } else {
                    state.selectedItems = []
                }
                state.changes = [.selection, .selectAll]
            }

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

        case .updateDownload(let update, let batchData):
            process(downloadUpdate: update, batchData: batchData, in: viewModel)

        case .updateAttachments(let notification):
            processAttachmentDeletion(notification: notification, in: viewModel)

        case .openAttachment(let attachment, let parentKey):
            open(attachment: attachment, parentKey: parentKey, in: viewModel)

        case .attachmentOpened(let key):
            guard viewModel.state.attachmentToOpen == key else { return }
            self.update(viewModel: viewModel) { state in
                state.attachmentToOpen = nil
            }
            
        case .cacheItemDataIfNeeded(let key):
            cacheItemData(key: key, viewModel: viewModel)
        }
    }

    private func loadData(in viewModel: ViewModel<TrashActionHandler>) {
        do {
            try dbStorage.perform(on: .main) { [weak self, weak viewModel] coordinator in
                guard let self, let viewModel else { return }

                let (library, libraryToken) = try viewModel.state.library.identifier.observe(in: coordinator, changes: { [weak self, weak viewModel] library in
                    guard let self, let viewModel else { return }
                    update(viewModel: viewModel) { state in
                        state.library = library
                        state.changes = .library
                    }
                })
                let snapshot = try createSnapshotAndObserve(
                    libraryId: viewModel.state.library.identifier,
                    sortType: viewModel.state.sortType,
                    filters: viewModel.state.filters,
                    searchTerm: viewModel.state.searchTerm,
                    titleFont: viewModel.state.titleFont,
                    coordinator: coordinator,
                    viewModel: viewModel
                )

                update(viewModel: viewModel) { state in
                    state.library = library
                    state.libraryToken = libraryToken
                    state.snapshot = snapshot
                    state.changes = .objects
                }
            }
        } catch let error {
            DDLogInfo("TrashActionHandler: can't load initial data - \(error)")
            update(viewModel: viewModel) { state in
                state.error = .dataLoading
            }
        }
    }

    private func createSnapshotAndObserve(
        libraryId: LibraryIdentifier,
        sortType: ItemsSortType,
        filters: [ItemsFilter],
        searchTerm: String?,
        titleFont: UIFont,
        coordinator: DbCoordinator,
        viewModel: ViewModel<TrashActionHandler>
    ) throws -> TrashState.Snapshot {
        let searchComponents = searchTerm.flatMap({ createComponents(from: $0) }) ?? []
        let itemsRequest = ReadItemsDbRequest(collectionId: .custom(.trash), libraryId: libraryId, filters: filters, sortType: sortType, searchTextComponents: searchComponents)
        let items = try coordinator.perform(request: itemsRequest)
        var collections: Results<RCollection>?
        if filters.isEmpty {
            let collectionsRequest = ReadCollectionsDbRequest(libraryId: libraryId, trash: true, searchTextComponents: searchComponents)
            collections = (try coordinator.perform(request: collectionsRequest)).sorted(by: collectionSortDescriptor(for: sortType))
        }
        let (keys, keyToIdx) = createSnapshotData(fromItems: items, collections: collections, sortType: sortType)
        let (itemsToken, collectionsToken) = observe(items: items, collections: collections, viewModel: viewModel)
        return TrashState.Snapshot(sortedKeys: keys, keyToIdx: keyToIdx, itemResults: items, itemsToken: itemsToken, collectionResults: collections, collectionsToken: collectionsToken)

        func collectionSortDescriptor(for sortType: ItemsSortType) -> [RealmSwift.SortDescriptor] {
            switch sortType.field {
            case .dateModified:
                return [
                    SortDescriptor(keyPath: "dateModified", ascending: sortType.ascending),
                    SortDescriptor(keyPath: "sortName", ascending: sortType.ascending)
                ]

            case .title, .creator, .date, .dateAdded, .itemType, .publisher, .publicationTitle, .year:
                return [SortDescriptor(keyPath: "sortName", ascending: sortType.ascending)]
            }
        }
    }

    private func createSnapshotData(fromItems items: Results<RItem>?, collections: Results<RCollection>?, sortType: ItemsSortType) -> ([TrashKey], [TrashKey: Int]) {
        var itemsIdx = 0
        var collectionsIdx = 0
        var keys: [TrashKey] = []
        var keyToIdx: [TrashKey: Int] = [:]
        if let collections, let items {
            while itemsIdx < items.count && collectionsIdx < collections.count {
                let item = items[itemsIdx]
                let collection = collections[collectionsIdx]
                if areInIncreasingOrder(lObject: item, rObject: collection, sortType: sortType) {
                    keys.append(TrashKey(type: .item, key: item.key))
                    keyToIdx[keys.last!] = itemsIdx
                    itemsIdx += 1
                } else {
                    keys.append(TrashKey(type: .collection, key: collection.key))
                    keyToIdx[keys.last!] = collectionsIdx
                    collectionsIdx += 1
                }
            }
        }
        if let collections {
            while collectionsIdx < collections.count {
                keys.append(TrashKey(type: .collection, key: collections[collectionsIdx].key))
                keyToIdx[keys.last!] = collectionsIdx
                collectionsIdx += 1
            }
        }
        if let items {
            while itemsIdx < items.count {
                keys.append(TrashKey(type: .item, key: items[itemsIdx].key))
                keyToIdx[keys.last!] = itemsIdx
                itemsIdx += 1
            }
        }
        return (keys, keyToIdx)
    }

    private func areInIncreasingOrder(lObject: TrashObject, rObject: TrashObject, sortType: ItemsSortType) -> Bool {
        let initialResult: ComparisonResult

        switch sortType.field {
        case .creator:
            initialResult = compare(lValue: lObject.creatorSummary, rValue: rObject.creatorSummary)

        case .date:
            initialResult = compare(lValue: lObject.date, rValue: rObject.date)

        case .dateAdded:
            initialResult = compare(lValue: lObject.dateAdded, rValue: rObject.dateAdded)

        case .dateModified:
            initialResult = compare(lValue: lObject.dateModified, rValue: rObject.dateModified)

        case .itemType:
            initialResult = compare(lValue: lObject.sortType, rValue: rObject.sortType)

        case .publicationTitle:
            initialResult = compare(lValue: lObject.publicationTitle, rValue: rObject.publicationTitle)

        case .publisher:
            DDLogInfo("LPublisher: \(lObject.key); '\(lObject.publisher ?? "nil")' - \(rObject.key); '\(rObject.publisher ?? "nil")'")
            initialResult = compare(lValue: lObject.publisher, rValue: rObject.publisher)

        case .year:
            initialResult = compare(lValue: lObject.year, rValue: rObject.year)

        case .title:
            return isInIncreasingOrder(result: compare(lValue: lObject.sortTitle, rValue: rObject.sortTitle), ascending: sortType.ascending, comparedSame: nil)
        }

        return isInIncreasingOrder(result: initialResult, ascending: sortType.ascending, comparedSame: { compare(lValue: lObject.sortTitle, rValue: rObject.sortTitle) })

        func isInIncreasingOrder(result: ComparisonResult, ascending: Bool, comparedSame: (() -> ComparisonResult)?) -> Bool {
            switch result {
            case .orderedSame:
                if let result = comparedSame?() {
                    return ascending ? result == .orderedAscending : result == .orderedDescending
                }
                return true

            case .orderedAscending:
                return ascending

            case .orderedDescending:
                return !ascending
            }
        }

        func compare<Val>(lValue: Val?, rValue: Val?, nonNilCompare: (Val, Val) -> ComparisonResult) -> ComparisonResult {
            if let lValue, let rValue {
                return nonNilCompare(lValue, rValue)
            }
            if lValue == nil && rValue == nil {
                return .orderedSame
            }
            if lValue != nil {
                return .orderedAscending
            }
            return .orderedDescending
        }

        func compare(lValue: String?, rValue: String?) -> ComparisonResult {
            return compare(lValue: lValue, rValue: rValue, nonNilCompare: { $0.compare($1, options: [.numeric], locale: Locale.autoupdatingCurrent) })
        }

        func compare(lValue: Int?, rValue: Int?) -> ComparisonResult {
            compare(lValue: lValue, rValue: rValue) { lValue, rValue in
                if lValue == rValue {
                    return .orderedSame
                }
                return lValue < rValue ? .orderedAscending : .orderedDescending
            }
        }

        func compare(lValue: Date?, rValue: Date?) -> ComparisonResult {
            return compare(lValue: lValue, rValue: rValue, nonNilCompare: { $0.compare($1) })
        }
    }

    private func observe(items: Results<RItem>?, collections: Results<RCollection>?, viewModel: ViewModel<TrashActionHandler>) -> (NotificationToken?, NotificationToken?) {
        let itemsToken = items?.observe(keyPaths: RItem.observableKeypathsForItemList, { [weak self, weak viewModel] changes in
            guard let self, let viewModel else { return }
            switch changes {
            case .update(let items, _, _, _):
                updateItems(items, viewModel: viewModel, handler: self)

            case .error(let error):
                DDLogError("TrashActionHandler: could not load items - \(error)")
                update(viewModel: viewModel) { state in
                    state.error = .dataLoading
                }

            case .initial:
                break
            }
        })

        let collectionsToken = collections?.observe(keyPaths: RCollection.observableKeypathsForList, { [weak self, weak viewModel] changes in
            guard let self, let viewModel else { return }
            switch changes {
            case .update(let collections, _, _, _):
                updateCollections(collections, viewModel: viewModel, handler: self)

            case .error(let error):
                DDLogError("TrashActionHandler: could not load collections - \(error)")
                update(viewModel: viewModel) { state in
                    state.error = .dataLoading
                }

            case .initial:
                break
            }
        })

        return (itemsToken, collectionsToken)

        func updateItems(_ items: Results<RItem>, viewModel: ViewModel<TrashActionHandler>, handler: TrashActionHandler) {
            let (keys, keyToIdx) = createSnapshotData(fromItems: items, collections: viewModel.state.snapshot.collectionResults, sortType: viewModel.state.sortType)
            handler.update(viewModel: viewModel) { state in
                state.snapshot = state.snapshot.updated(sortedKeys: keys, keyToIdx: keyToIdx, items: items.freeze())
                state.changes = .objects
            }
        }

        func updateCollections(_ collections: Results<RCollection>, viewModel: ViewModel<TrashActionHandler>, handler: TrashActionHandler) {
            let (keys, keyToIdx) = createSnapshotData(fromItems: viewModel.state.snapshot.itemResults, collections: collections, sortType: viewModel.state.sortType)
            handler.update(viewModel: viewModel) { state in
                state.snapshot = state.snapshot.updated(sortedKeys: keys, keyToIdx: keyToIdx, collections: collections.freeze())
                state.changes = .objects
            }
        }
    }

    // MARK: - Actions

    private func cacheItemData(key: TrashKey, viewModel: ViewModel<TrashActionHandler>) {
        guard let object = viewModel.state.snapshot.object(for: key) else { return }
        let cachedData = viewModel.state.itemDataCache[key]
        var title: NSAttributedString? = cachedData?.title
        var accessory: ItemAccessory? = cachedData?.accessory
        if title == nil {
            title = htmlAttributedStringConverter.convert(text: object.displayTitle, baseAttributes: [.font: viewModel.state.titleFont])
        }
        if accessory == nil, let item = object as? RItem {
            accessory = ItemAccessory.create(from: item, fileStorage: fileStorage, urlDetector: urlDetector)
        }
        update(viewModel: viewModel) { state in
            state.itemDataCache[key] = TrashState.ItemData(title: title, accessory: accessory)
        }
    }

    private func split(keys: Set<TrashKey>) -> (items: [String], collections: [String]) {
        var items: [String] = []
        var collections: [String] = []
        for key in keys {
            switch key.type {
            case .collection:
                collections.append(key.key)

            case .item:
                items.append(key.key)
            }
        }
        return (items, collections)
    }

    private func emptyTrash(in viewModel: ViewModel<TrashActionHandler>) {
        self.perform(request: EmptyTrashDbRequest(libraryId: viewModel.state.library.identifier)) { error in
            guard let error = error else { return }
            // TODO: - show error
            DDLogError("ItemsActionHandler: can't empty trash - \(error)")
        }
    }

    private func delete(objects keys: Set<TrashKey>, viewModel: ViewModel<TrashActionHandler>) {
        let (items, collections) = split(keys: keys)
        var requests: [DbRequest] = []
        if !items.isEmpty {
            requests.append(MarkObjectsAsDeletedDbRequest<RItem>(keys: items, libraryId: viewModel.state.library.identifier))
        }
        if !collections.isEmpty {
            requests.append(MarkObjectsAsDeletedDbRequest<RCollection>(keys: collections, libraryId: viewModel.state.library.identifier))
        }

        perform(writeRequests: requests) { [weak self, weak viewModel] error in
            guard let self, let viewModel, let error else { return }
            DDLogError("TrashActionHandler: can't delete objects - \(error)")
            update(viewModel: viewModel) { state in
                state.error = .deletion
            }
        }
    }

    private func set(trashed: Bool, to keys: Set<TrashKey>, libraryId: LibraryIdentifier, completion: @escaping (Result<Void, ItemsError>) -> Void) {
        let (items, collections) = split(keys: keys)
        var requests: [DbRequest] = []
        if !items.isEmpty {
            requests.append(MarkItemsAsTrashedDbRequest(keys: items, libraryId: libraryId, trashed: trashed))
        }
        if !collections.isEmpty {
            requests.append(MarkCollectionsAsTrashedDbRequest(keys: collections, libraryId: libraryId, trashed: trashed))
        }
        perform(writeRequests: requests) { error in
            guard let error else { return }
            DDLogError("TrashActionHandler: can't trash objects - \(error)")
            completion(.failure(.deletion))
        }
    }

    private func startEditing(in viewModel: ViewModel<TrashActionHandler>) {
        update(viewModel: viewModel) { state in
            state.isEditing = true
            state.changes.insert(.editing)
        }
    }

    private func stopEditing(in viewModel: ViewModel<TrashActionHandler>) {
        update(viewModel: viewModel) { state in
            state.isEditing = false
            state.selectedItems.removeAll()
            state.changes.insert(.editing)
        }
    }

    // MARK: - Downloads

    private func downloadAttachments(for keys: Set<TrashKey>, in viewModel: ViewModel<TrashActionHandler>) {
        var attachments: [(Attachment, String?)] = []
        for key in keys {
            guard let attachment = viewModel.state.itemDataCache[key]?.accessory?.attachment else { continue }
            let parentKey = attachment.key == key.key ? nil : key.key
            attachments.append((attachment, parentKey))
        }
        fileDownloader.batchDownload(attachments: attachments)
    }

    private func process(downloadUpdate: AttachmentDownloader.Update, batchData: ItemsState.DownloadBatchData?, in viewModel: ViewModel<TrashActionHandler>) {
        let updateKey = TrashKey(type: .item, key: downloadUpdate.parentKey ?? downloadUpdate.key)
        guard let itemData = viewModel.state.itemDataCache[updateKey], let attachment = itemData.accessory?.attachment, attachment.key == downloadUpdate.key else {
            updateViewModel()
            return
        }

        switch downloadUpdate.kind {
        case .ready(let compressed):
            DDLogInfo("TrashActionHandler: download update \(attachment.key); \(attachment.libraryId); kind \(downloadUpdate.kind)")
            guard let updatedAttachment = attachment.changed(location: .local, compressed: compressed) else { return }
            updateViewModel { state in
                state.itemDataCache[updateKey] = TrashState.ItemData(title: itemData.title, accessory: .attachment(attachment: updatedAttachment, parentKey: downloadUpdate.parentKey))
                state.updateItemKey = updateKey
            }

        case .progress:
            // If file is being extracted, the extraction is usually very quick and sends multiple quick progress updates, due to switching between queues and small delays those updates are then
            // received here, but the file downloader is already done and we're unnecessarily reloading the table view with the same progress. So we're filtering out those unnecessary updates
            guard
                let currentProgress = fileDownloader.data(for: downloadUpdate.key, parentKey: downloadUpdate.parentKey, libraryId: downloadUpdate.libraryId).progress,
                currentProgress < 1
            else { return }
            updateViewModel { state in
                state.updateItemKey = updateKey
            }

        case .cancelled, .failed:
            DDLogInfo("TrashActionHandler: download update \(attachment.key); \(attachment.libraryId); kind \(downloadUpdate.kind)")
            updateViewModel { state in
                state.updateItemKey = updateKey
            }
        }

        func updateViewModel(additional: ((inout TrashState) -> Void)? = nil) {
            update(viewModel: viewModel) { state in
                if state.downloadBatchData != batchData {
                    state.downloadBatchData = batchData
                    state.changes = .batchData
                }
                additional?(&state)
            }
        }
    }

    private func processAttachmentDeletion(notification: AttachmentFileDeletedNotification, in viewModel: ViewModel<TrashActionHandler>) {
        switch notification {
        case .all:
            // Update all attachment locations to `.remote`.
            self.update(viewModel: viewModel) { state in
                changeAttachmentsToRemoteLocation(in: &state)
                state.changes = .attachmentsRemoved
            }

        case .library(let libraryId):
            // Check whether files in this library have been deleted.
            guard viewModel.state.library.identifier == libraryId else { return }
            // Update all attachment locations to `.remote`.
            self.update(viewModel: viewModel) { state in
                changeAttachmentsToRemoteLocation(in: &state)
                state.changes = .attachmentsRemoved
            }

        case .allForItems(let keys, let libraryId):
            // Check whether files in this library have been deleted.
            guard viewModel.state.library.identifier == libraryId else { return }
            update(viewModel: viewModel) { state in
                changeAttachmentsToRemoteLocation(for: keys, in: &state)
                state.changes = .attachmentsRemoved
            }

        case .individual(let key, let parentKey, let libraryId):
            let updateKey = parentKey ?? key
            let trashKey = TrashKey(type: .item, key: updateKey)
            // Check whether the deleted file was in this library and there is a cached object for it.
            guard viewModel.state.library.identifier == libraryId && viewModel.state.snapshot.keyToIdx[trashKey] != nil else { return }
            update(viewModel: viewModel) { state in
                changeAttachmentsToRemoteLocation(for: [updateKey], in: &state)
                state.updateItemKey = trashKey
            }
        }

        func changeAttachmentsToRemoteLocation(for keys: Set<String>? = nil, in state: inout TrashState) {
            if let keys {
                for key in keys {
                    let trashKey = TrashKey(type: .item, key: key)
                    guard
                        let data = state.itemDataCache[trashKey],
                        let newAccessory = data.accessory?.updatedAttachment(update: { attachment in attachment.changed(location: .remote, condition: { $0 == .local }) })
                    else { continue }
                    state.itemDataCache[trashKey] = TrashState.ItemData(title: data.title, accessory: newAccessory)
                }
            } else {
                for (key, data) in state.itemDataCache {
                    guard
                        key.type == .item,
                        let newAccessory = data.accessory?.updatedAttachment(update: { attachment in attachment.changed(location: .remote, condition: { $0 == .local }) })
                    else { continue }
                    state.itemDataCache[key] = TrashState.ItemData(title: data.title, accessory: newAccessory)
                }
            }
        }
    }

    private func open(attachment: Attachment, parentKey: String?, in viewModel: ViewModel<TrashActionHandler>) {
        let (progress, _) = fileDownloader.data(for: attachment.key, parentKey: parentKey, libraryId: attachment.libraryId)
        if progress != nil {
            if viewModel.state.attachmentToOpen == attachment.key {
                self.update(viewModel: viewModel) { state in
                    state.attachmentToOpen = nil
                }
            }

            fileDownloader.cancel(key: attachment.key, parentKey: parentKey, libraryId: attachment.libraryId)
        } else {
            update(viewModel: viewModel) { state in
                state.attachmentToOpen = attachment.key
            }
            fileDownloader.downloadIfNeeded(attachment: attachment, parentKey: parentKey, retryIfNeeded: false)
        }
    }

    // MARK: - Searching & Filtering

    private func search(with term: String?, in viewModel: ViewModel<TrashActionHandler>) {
        guard term != viewModel.state.searchTerm else { return }
        updateState(searchTerm: term, filters: viewModel.state.filters, sortType: viewModel.state.sortType, in: viewModel)
    }

    private func filter(with filters: [ItemsFilter], in viewModel: ViewModel<TrashActionHandler>) {
        guard filters != viewModel.state.filters else { return }
        updateState(searchTerm: viewModel.state.searchTerm, filters: filters, sortType: viewModel.state.sortType, in: viewModel)
    }

    private func changeSortType(to sortType: ItemsSortType, in viewModel: ViewModel<TrashActionHandler>) {
        guard sortType != viewModel.state.sortType else { return }
        updateState(searchTerm: viewModel.state.searchTerm, filters: viewModel.state.filters, sortType: sortType, in: viewModel)
        Defaults.shared.itemsSortType = sortType
    }

    private func updateState(
        searchTerm: String?,
        filters: [ItemsFilter],
        sortType: ItemsSortType,
        in viewModel: ViewModel<TrashActionHandler>
    ) {
        try? dbStorage.perform(on: .main) { [weak self, weak viewModel] coordinator in
            guard let self, let viewModel else { return }
            let snapshot = try createSnapshotAndObserve(
                libraryId: viewModel.state.library.identifier,
                sortType: sortType,
                filters: filters,
                searchTerm: searchTerm,
                titleFont: viewModel.state.titleFont,
                coordinator: coordinator,
                viewModel: viewModel
            )
            update(viewModel: viewModel) { state in
                state.snapshot = snapshot
                state.changes = .objects
                state.searchTerm = searchTerm
                state.sortType = sortType
                if state.filters != filters {
                    state.filters = filters
                    state.changes.insert(.filters)
                }
            }
        }
    }
}
