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

struct TrashActionHandler: ViewModelActionHandler, BackgroundDbProcessingActionHandler {
    typealias State = TrashState
    typealias Action = TrashAction

    unowned let dbStorage: DbStorage
    private unowned let fileStorage: FileStorage
    private unowned let urlDetector: UrlDetector

    var backgroundQueue: DispatchQueue

    init(dbStorage: DbStorage, fileStorage: FileStorage, urlDetector: UrlDetector) {
        self.dbStorage = dbStorage
        self.fileStorage = fileStorage
        self.urlDetector = urlDetector
        backgroundQueue = DispatchQueue(label: "org.zotero.Zotero.TrashActionHandler.queue", qos: .userInteractive)
    }

    func process(action: TrashAction, in viewModel: ViewModel<TrashActionHandler>) {
        switch action {
        case .loadData:
            loadData(in: viewModel)
        }
    }

    private func loadData(in viewModel: ViewModel<TrashActionHandler>) {
        do {
            let sortType = Defaults.shared.itemsSortType
            let items = try dbStorage.perform(request: ReadItemsDbRequest(collectionId: .custom(.trash), libraryId: viewModel.state.library.identifier, sortType: sortType), on: .main)
            let collectionsRequest = ReadCollectionsDbRequest(libraryId: viewModel.state.library.identifier, trash: true)
            let collections = (try dbStorage.perform(request: collectionsRequest, on: .main)).sorted(by: collectionSortDescriptor(for: sortType))

            var objects: OrderedDictionary<TrashKey, TrashObject> = [:]
            for object in items.compactMap({ trashObject(from: $0) }) {
                objects[object.trashKey] = object
            }
            for collection in collections {
                guard let object = trashObject(from: collection) else { continue }
                let index = objects.index(of: object, sortedBy: { areInIncreasingOrder(lObject: $0, rObject: $1, sortType: sortType) })
                objects.updateValue(object, forKey: object.trashKey, insertingAt: index)
            }

            update(viewModel: viewModel) { state in
                state.objects = objects
            }
        } catch let error {
            DDLogInfo("TrashActionHandler: can't load initial data - \(error)")
            update(viewModel: viewModel) { state in
                state.error = .dataLoading
            }
        }

        func areInIncreasingOrder(lObject: TrashObject, rObject: TrashObject, sortType: ItemsSortType) -> Bool {
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
                if let lValue {
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
                if let lValue {
                    return .orderedAscending
                }
                return .orderedDescending
            }

            func compare(lValue: Date?, rValue: Date?) -> ComparisonResult {
                if let lValue, let rValue {
                    return lValue.compare(rValue)
                }
                if let lValue {
                    return .orderedAscending
                }
                return .orderedDescending
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

        func trashObject(from collection: RCollection) -> TrashObject? {
            guard let libraryId = collection.libraryId else { return nil }
            return TrashObject(type: .collection, key: collection.key, libraryId: libraryId, title: collection.name, dateModified: collection.dateModified)
        }

        func trashObject(from item: RItem) -> TrashObject? {
            guard let libraryId = item.libraryId else { return nil }
            let accessory = ItemAccessory.create(from: item, fileStorage: fileStorage, urlDetector: urlDetector).flatMap({ convertToItemCellModelAccessory(accessory: $0) })
            let creatorSummary = ItemCellModel.creatorSummary(for: item)
            let (tagColors, tagEmojis) = ItemCellModel.tagData(item: item)
            let hasNote = ItemCellModel.hasNote(item: item)
            let cellData = TrashObject.ItemCellData(
                typeIconName: ItemCellModel.typeIconName(for: item),
                subtitle: creatorSummary,
                accessory: accessory,
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
            return TrashObject(type: .item(cellData: cellData, sortData: sortData), key: item.key, libraryId: libraryId, title: item.displayTitle, dateModified: item.dateModified)
        }

        func convertToItemCellModelAccessory(accessory: ItemAccessory?) -> ItemCellModel.Accessory? {
            guard let accessory else { return nil }
            switch accessory {
            case .attachment(let attachment, _):
                return .attachment(.stateFrom(type: attachment.type, progress: nil, error: nil))

            case .doi:
                return .doi

            case .url:
                return .url
            }
        }
    }
}
