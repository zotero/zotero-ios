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

    init(
        dbStorage: DbStorage,
        schemaController: SchemaController,
        fileStorage: FileStorage,
        fileDownloader: AttachmentDownloader,
        urlDetector: UrlDetector,
        htmlAttributedStringConverter: HtmlAttributedStringConverter
    ) {
        self.schemaController = schemaController
        self.fileStorage = fileStorage
        self.fileDownloader = fileDownloader
        self.urlDetector = urlDetector
        self.htmlAttributedStringConverter = htmlAttributedStringConverter
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
                if state.selectedItems.count != state.objects.count {
                    state.selectedItems = Set(state.objects.keys)
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

        case .openAttachment(let attachment, let parentKey):
            open(attachment: attachment, parentKey: parentKey, in: viewModel)

        case .attachmentOpened(let key):
            guard viewModel.state.attachmentToOpen == key else { return }
            self.update(viewModel: viewModel) { state in
                state.attachmentToOpen = nil
            }
        }
    }

    private func loadData(in viewModel: ViewModel<TrashActionHandler>) {
        do {
            let items = try dbStorage.perform(request: ReadItemsDbRequest(collectionId: .custom(.trash), libraryId: viewModel.state.library.identifier, sortType: viewModel.state.sortType), on: .main)
            let collectionsRequest = ReadCollectionsDbRequest(libraryId: viewModel.state.library.identifier, trash: true)
            let collections = (try dbStorage.perform(request: collectionsRequest, on: .main)).sorted(by: collectionSortDescriptor(for: viewModel.state.sortType))
            let results = results(
                fromItems: items,
                collections: collections,
                sortType: viewModel.state.sortType,
                filters: viewModel.state.filters,
                searchTerm: viewModel.state.searchTerm,
                titleFont: viewModel.state.titleFont
            )
            update(viewModel: viewModel) { state in
                state.objects = results
            }
        } catch let error {
            DDLogInfo("TrashActionHandler: can't load initial data - \(error)")
            update(viewModel: viewModel) { state in
                state.error = .dataLoading
            }
        }

        func collectionSortDescriptor(for sortType: ItemsSortType) -> [RealmSwift.SortDescriptor] {
            switch sortType.field {
            case .dateModified:
                return [
                    SortDescriptor(keyPath: "dateModified", ascending: sortType.ascending),
                    SortDescriptor(keyPath: "name", ascending: sortType.ascending)
                ]

            case .title, .creator, .date, .dateAdded, .itemType, .publisher, .publicationTitle, .year:
                return [SortDescriptor(keyPath: "name", ascending: sortType.ascending)]
            }
        }

        func results(
            fromItems items: Results<RItem>,
            collections: Results<RCollection>,
            sortType: ItemsSortType,
            filters: [ItemsFilter],
            searchTerm: String?,
            titleFont: UIFont
        ) -> OrderedDictionary<TrashKey, TrashObject> {
            var objects: OrderedDictionary<TrashKey, TrashObject> = [:]
            for object in items.compactMap({ trashObject(from: $0, titleFont: titleFont) }) {
                objects[object.trashKey] = object
            }
            for collection in collections {
                guard let object = trashObject(from: collection, titleFont: titleFont) else { continue }
                let index = objects.index(of: object, sortedBy: { areInIncreasingOrder(lObject: $0, rObject: $1, sortType: sortType) })
                objects.updateValue(object, forKey: object.trashKey, insertingAt: index)
            }
            return objects
        }

        func trashObject(from collection: RCollection, titleFont: UIFont) -> TrashObject? {
            guard let libraryId = collection.libraryId else { return nil }
            let attributedTitle = htmlAttributedStringConverter.convert(text: collection.name, baseAttributes: [.font: titleFont])
            return TrashObject(type: .collection, key: collection.key, libraryId: libraryId, title: attributedTitle, dateModified: collection.dateModified)
        }

        func trashObject(from rItem: RItem, titleFont: UIFont) -> TrashObject? {
            guard let libraryId = rItem.libraryId else { return nil }
            let itemAccessory = ItemAccessory.create(from: rItem, fileStorage: fileStorage, urlDetector: urlDetector)
            let cellAccessory = itemAccessory.flatMap({ ItemCellModel.createAccessory(from: $0, fileDownloader: fileDownloader) })
            let creatorSummary = ItemCellModel.creatorSummary(for: rItem)
            let (tagColors, tagEmojis) = ItemCellModel.tagData(item: rItem)
            let hasNote = ItemCellModel.hasNote(item: rItem)
            let typeName = schemaController.localized(itemType: rItem.rawType) ?? rItem.rawType
            let attributedTitle = htmlAttributedStringConverter.convert(text: rItem.displayTitle, baseAttributes: [.font: titleFont])
            let item = TrashObject.Item(
                sortTitle: rItem.sortTitle,
                type: rItem.rawType,
                localizedTypeName: typeName,
                typeIconName: ItemCellModel.typeIconName(for: rItem),
                creatorSummary: creatorSummary,
                publisher: rItem.publisher,
                publicationTitle: rItem.publicationTitle,
                year: rItem.hasParsedYear ? rItem.parsedYear : nil,
                date: rItem.parsedDate,
                dateAdded: rItem.dateAdded,
                tagNames: Set(rItem.tags.compactMap({ $0.tag?.name })),
                tagColors: tagColors,
                tagEmojis: tagEmojis,
                hasNote: hasNote,
                itemAccessory: itemAccessory,
                cellAccessory: cellAccessory,
                isMainAttachmentDownloaded: rItem.fileDownloaded,
                searchStrings: searchStrings(from: rItem)
            )
            return TrashObject(type: .item(item: item), key: rItem.key, libraryId: libraryId, title: attributedTitle, dateModified: rItem.dateModified)

            func searchStrings(from item: RItem) -> Set<String> {
                var strings: Set<String> = [item.key, item.sortTitle]
                if let value = item.htmlFreeContent {
                    strings.insert(value)
                }
                for creator in item.creators {
                    if !creator.name.isEmpty {
                        strings.insert(creator.name)
                    }
                    if !creator.firstName.isEmpty {
                        strings.insert(creator.firstName)
                    }
                    if !creator.lastName.isEmpty {
                        strings.insert(creator.lastName)
                    }
                }
                for tag in item.tags {
                    guard let name = tag.tag?.name else { continue }
                    strings.insert(name)
                }
                for field in item.fields {
                    strings.insert(field.value)
                }
                for child in item.children {
                    strings.formUnion(searchStrings(from: child))
                }
                return strings
            }
        }
    }

    private func results(
        fromOriginal original: OrderedDictionary<TrashKey, TrashObject>,
        sortType: ItemsSortType,
        filters: [ItemsFilter],
        searchTerm: String?
    ) -> OrderedDictionary<TrashKey, TrashObject> {
        var results: OrderedDictionary<TrashKey, TrashObject> = [:]
        for (key, value) in original {
            guard object(value, containsTerm: searchTerm) && object(value, satisfiesFilters: filters) else { continue }
            let index = results.index(of: value, sortedBy: { areInIncreasingOrder(lObject: $0, rObject: $1, sortType: sortType) })
            results.updateValue(value, forKey: key, insertingAt: index)
        }
        return original

        func object(_ object: TrashObject, satisfiesFilters filters: [ItemsFilter]) -> Bool {
            guard !filters.isEmpty else { return true }

            for filter in filters {
                switch object.type {
                case .collection:
                    // Collections don't have tags or can be "downloaded", so they fail automatically
                    return false

                case .item(let item):
                    switch filter {
                    case .downloadedFiles:
                        if !item.isMainAttachmentDownloaded {
                            return false
                        }

                    case .tags(let tagNames):
                        if item.tagNames.intersection(tagNames).isEmpty {
                            return false
                        }
                    }
                }
            }

            return true
        }

        func object(_ object: TrashObject, containsTerm term: String?) -> Bool {
            guard let term else { return true }
            let components = createComponents(from: term)
            guard !components.isEmpty else { return true }
            for component in components {
                switch object.type {
                case .item(let item):
                    for string in item.searchStrings {
                        if string == component || string.localizedCaseInsensitiveContains(component) {
                            return true
                        }
                    }

                case .collection:
                    if component.lowercased() == "collection" {
                        return true
                    }
                    if object.key == component {
                        return true
                    }
                    if object.title.string.localizedCaseInsensitiveContains(component) {
                        return true
                    }
                }
            }
            return false
        }
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

        func compare(lValue: String?, rValue: String?) -> ComparisonResult {
            if let lValue, let rValue {
                return lValue.compare(rValue, options: [.numeric], locale: Locale.autoupdatingCurrent)
            }
            if lValue != nil {
                return .orderedAscending
            }
            return .orderedDescending
        }

        func compare(lValue: Int?, rValue: Int?) -> ComparisonResult {
            if let lValue, let rValue {
                if lValue == rValue {
                    return .orderedSame
                }
                return lValue < rValue ? .orderedAscending : .orderedDescending
            }
            if lValue != nil {
                return .orderedAscending
            }
            return .orderedDescending
        }

        func compare(lValue: Date?, rValue: Date?) -> ComparisonResult {
            if let lValue, let rValue {
                return lValue.compare(rValue)
            }
            if lValue != nil {
                return .orderedAscending
            }
            return .orderedDescending
        }
    }

    // MARK: - Actions

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

    private func downloadAttachments(for keys: Set<String>, in viewModel: ViewModel<TrashActionHandler>) {
        var attachments: [(Attachment, String?)] = []
        for key in keys {
            guard let attachment = viewModel.state.objects[TrashKey(type: .item, key: key)]?.itemAccessory?.attachment else { continue }
            let parentKey = attachment.key == key ? nil : key
            attachments.append((attachment, parentKey))
        }
        fileDownloader.batchDownload(attachments: attachments)
    }

    private func process(downloadUpdate: AttachmentDownloader.Update, batchData: ItemsState.DownloadBatchData?, in viewModel: ViewModel<TrashActionHandler>) {
        let updateKey = TrashKey(type: .item, key: downloadUpdate.parentKey ?? downloadUpdate.key)
        guard let accessory = viewModel.state.objects[updateKey]?.itemAccessory, let attachment = accessory.attachment else {
            updateViewModel()
            return
        }

        switch downloadUpdate.kind {
        case .ready(let compressed):
            DDLogInfo("TrashActionHandler: download update \(attachment.key); \(attachment.libraryId); kind \(downloadUpdate.kind)")
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
            fileDownloader.downloadIfNeeded(attachment: attachment, parentKey: parentKey)
        }
    }

    // MARK: - Searching & Filtering

    private func search(with term: String?, in viewModel: ViewModel<TrashActionHandler>) {
        guard term != viewModel.state.searchTerm else { return }
        let results = results(
            fromOriginal: viewModel.state.snapshot ?? viewModel.state.objects,
            sortType: viewModel.state.sortType,
            filters: viewModel.state.filters,
            searchTerm: term
        )
        updateState(withResults: results, in: viewModel) { state in
            state.searchTerm = term
        }
    }

    private func filter(with filters: [ItemsFilter], in viewModel: ViewModel<TrashActionHandler>) {
        guard filters != viewModel.state.filters else { return }
        let results = results(
            fromOriginal: viewModel.state.snapshot ?? viewModel.state.objects,
            sortType: viewModel.state.sortType,
            filters: filters,
            searchTerm: viewModel.state.searchTerm
        )
        updateState(withResults: results, in: viewModel) { state in
            state.filters = filters
            state.changes.insert(.filters)
        }
    }

    private func changeSortType(to sortType: ItemsSortType, in viewModel: ViewModel<TrashActionHandler>) {
        guard sortType != viewModel.state.sortType else { return }
        var ordered: OrderedDictionary<TrashKey, TrashObject> = [:]
        for object in viewModel.state.objects {
            let index = ordered.index(of: object.value, sortedBy: { areInIncreasingOrder(lObject: $0, rObject: $1, sortType: sortType) })
            ordered.updateValue(object.value, forKey: object.key, insertingAt: index)
        }
        updateState(withResults: ordered, in: viewModel) { state in
            state.sortType = sortType
        }
        Defaults.shared.itemsSortType = sortType
    }

    private func updateState(withResults results: OrderedDictionary<TrashKey, TrashObject>, in viewModel: ViewModel<TrashActionHandler>, additionalStateUpdate: (inout TrashState) -> Void) {
        update(viewModel: viewModel) { state in
            if state.snapshot == nil {
                state.snapshot = state.objects
            }
            state.objects = results
            state.changes = [.objects]
            additionalStateUpdate(&state)
        }
    }
}
