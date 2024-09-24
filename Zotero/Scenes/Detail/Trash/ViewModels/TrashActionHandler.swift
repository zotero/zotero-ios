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

        case .deleteItems(let keys):
            delete(items: keys, viewModel: viewModel)

        case .emptyTrash:
            emptyTrash(in: viewModel)

        case .tagItem(let itemKey, let libraryId, let tagNames):
            tagItem(key: itemKey, libraryId: libraryId, with: tagNames)

        case .assignItemsToCollections(let items, let collections):
            add(items: items, to: collections, libraryId: viewModel.state.library.identifier, completion: handleBaseActionResult)

        case .deleteItemsFromCollection(let keys):
            deleteItemsFromCollection(keys: keys, collectionId: .custom(.trash), libraryId: viewModel.state.library.identifier, completion: handleBaseActionResult)

        case .moveItems(let keys, let toItemKey):
            moveItems(from: keys, to: toItemKey, libraryId: viewModel.state.library.identifier, completion: handleBaseActionResult)

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

        case .setSortField(let field):
            changeSortType(to: ItemsSortType(field: field, ascending: field.defaultOrderAscending), in: viewModel)

        case .setSortOrder(let ascending):
            var type = viewModel.state.sortType
            type.ascending = ascending
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

        func trashObject(from item: RItem, titleFont: UIFont) -> TrashObject? {
            guard let libraryId = item.libraryId else { return nil }
            let itemAccessory = ItemAccessory.create(from: item, fileStorage: fileStorage, urlDetector: urlDetector)
            let cellAccessory = itemAccessory.flatMap({ ItemCellModel.createAccessory(from: $0, fileDownloader: fileDownloader) })
            let creatorSummary = ItemCellModel.creatorSummary(for: item)
            let (tagColors, tagEmojis) = ItemCellModel.tagData(item: item)
            let hasNote = ItemCellModel.hasNote(item: item)
            let typeName = schemaController.localized(itemType: item.rawType) ?? item.rawType
            let attributedTitle = htmlAttributedStringConverter.convert(text: item.displayTitle, baseAttributes: [.font: titleFont])
            let cellData = TrashObject.ItemCellData(
                localizedTypeName: typeName,
                typeIconName: ItemCellModel.typeIconName(for: item),
                subtitle: creatorSummary,
                accessory: cellAccessory,
                tagColors: tagColors,
                tagEmojis: tagEmojis,
                hasNote: hasNote
            )
            let sortData = TrashObject.ItemSortData(
                title: item.sortTitle,
                type: item.localizedType,
                creatorSummary: creatorSummary,
                publisher: item.publisher,
                publicationTitle: item.publicationTitle,
                year: item.hasParsedYear ? item.parsedYear : nil,
                date: item.parsedDate,
                dateAdded: item.dateAdded
            )
            return TrashObject(type: .item(cellData: cellData, sortData: sortData, accessory: itemAccessory), key: item.key, libraryId: libraryId, title: attributedTitle, dateModified: item.dateModified)
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

                case .item(let cellData, let sortData, let accessory):
                    switch filter {
                    case .downloadedFiles:
                        continue

                    case .tags(let tagNames):
                        continue
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
                // If object contains component somewhere, return true, otherwise continue
//                let keyPredicate = NSPredicate(format: "key == %@", text)
//                let childrenKeyPredicate = NSPredicate(format: "any children.key == %@", text)
//                // TODO: - ideally change back to "==" if Realm issue is fixed
//                let childrenChildrenKeyPredicate = NSPredicate(format: "any children.children.key contains %@", text)
//                let contentPredicate = NSPredicate(format: "htmlFreeContent contains[c] %@", text)
//                let childrenContentPredicate = NSPredicate(format: "any children.htmlFreeContent contains[c] %@", text)
//                let childrenChildrenContentPredicate = NSPredicate(format: "any children.children.htmlFreeContent contains[c] %@", text)
//                let titlePredicate = NSPredicate(format: "sortTitle contains[c] %@", text)
//                let childrenTitlePredicate = NSPredicate(format: "any children.sortTitle contains[c] %@", text)
//                let creatorFullNamePredicate = NSPredicate(format: "any creators.name contains[c] %@", text)
//                let creatorFirstNamePredicate = NSPredicate(format: "any creators.firstName contains[c] %@", text)
//                let creatorLastNamePredicate = NSPredicate(format: "any creators.lastName contains[c] %@", text)
//                let tagPredicate = NSPredicate(format: "any tags.tag.name contains[c] %@", text)
//                let childrenTagPredicate = NSPredicate(format: "any children.tags.tag.name contains[c] %@", text)
//                let childrenChildrenTagPredicate = NSPredicate(format: "any children.children.tags.tag.name contains[c] %@", text)
//                let fieldsPredicate = NSPredicate(format: "any fields.value contains[c] %@", text)
//                let childrenFieldsPredicate = NSPredicate(format: "any children.fields.value contains[c] %@", text)
//                let childrenChildrenFieldsPredicate = NSPredicate(format: "any children.children.fields.value contains[c] %@", text)
//
//                var predicates = [
//                    keyPredicate,
//                    titlePredicate,
//                    contentPredicate,
//                    creatorFullNamePredicate,
//                    creatorFirstNamePredicate,
//                    creatorLastNamePredicate,
//                    tagPredicate,
//                    childrenKeyPredicate,
//                    childrenTitlePredicate,
//                    childrenContentPredicate,
//                    childrenTagPredicate,
//                    childrenChildrenKeyPredicate,
//                    childrenChildrenContentPredicate,
//                    childrenChildrenTagPredicate,
//                    fieldsPredicate,
//                    childrenFieldsPredicate,
//                    childrenChildrenFieldsPredicate
//                ]
//
//                if let int = Int(text) {
//                    let yearPredicate = NSPredicate(format: "parsedYear == %d", int)
//                    predicates.insert(yearPredicate, at: 3)
//                }
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

    private func delete(items keys: Set<String>, viewModel: ViewModel<TrashActionHandler>) {
        let request = MarkObjectsAsDeletedDbRequest<RItem>(keys: Array(keys), libraryId: viewModel.state.library.identifier)
        self.perform(request: request) { [weak self, weak viewModel] error in
            guard let self, let viewModel, let error else { return }
            DDLogError("BaseItemsActionHandler: can't delete items - \(error)")
            update(viewModel: viewModel) { state in
                state.error = .deletion
            }
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
