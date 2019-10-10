//
//  ItemsStore.swift
//  Zotero
//
//  Created by Michal Rentka on 11/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import Foundation

import CocoaLumberjack
import RealmSwift
import RxSwift

class ItemsStore: ObservableObject {
    enum Error: Swift.Error, Equatable {
        case dataLoading, deletion
    }

    struct State {
        enum ItemType {
            case all, trash, publications
            case collection(String, String) // Key, Title
            case search(String, String) // Key, Title

            var collectionKey: String? {
                switch self {
                case .collection(let key, _):
                    return key
                default:
                    return nil
                }
            }

            var isTrash: Bool {
                switch self {
                case .trash:
                    return true
                default:
                    return false
                }
            }
        }

        let type: ItemType
        let library: Library

        fileprivate(set) var sections: [String]?
        fileprivate var results: Results<RItem>?
        fileprivate(set) var error: Error?
        fileprivate var itemsToken: NotificationToken?
        var sortType: ItemsSortType {
            willSet {
                if let results = self.results {
                    self.sections = ItemsStore.sections(from: results, sortType: newValue)
                }
            }
        }
        var selectedItems: Set<String> = []
        var menuActionSheetPresented: Bool = false
        var showingCreation: Bool = false {
            willSet {
                self.menuActionSheetPresented = false
            }
        }

        func items(for section: String) -> Results<RItem>? {
            if section == "-" {
                return self.results?.filter("title == ''").sorted(by: self.sortType.descriptors)
            } else {
                return self.results?.filter("title BEGINSWITH[c] %@", section).sorted(by: self.sortType.descriptors)
            }
        }
    }

    var state: State {
        willSet {
            self.objectWillChange.send()
        }
    }
    // SWIFTUI BUG: should be defined by default, but bugged in current version
    let objectWillChange: ObservableObjectPublisher
    private let dbStorage: DbStorage

    init(type: State.ItemType, library: Library, dbStorage: DbStorage) {
        self.objectWillChange = ObservableObjectPublisher()
        self.dbStorage = dbStorage

        do {
            let items = try dbStorage.createCoordinator().perform(request: ItemsStore.request(for: type, libraryId: library.identifier))
            let sortType = ItemsSortType(field: .title, ascending: true)

            self.state = State(type: type,
                               library: library,
                               sections: ItemsStore.sections(from: items, sortType: sortType),
                               results: items,
                               sortType: sortType)

            let token = items.observe { [weak self] changes in
                switch changes {
                case .error: break
                case .initial: break
                case .update(let results, _, _, _):
                    guard let `self` = self else { return }
                    self.state.results = results
                    self.state.sections = ItemsStore.sections(from: results, sortType: self.state.sortType)
                }
            }
            self.state.itemsToken = token
        } catch let error {
            DDLogError("ItemStore: can't load items - \(error)")
            self.state = State(type: type,
                               library: library,
                               error: .dataLoading,
                               sortType: ItemsSortType(field: .title, ascending: true))
        }
    }

    func trashSelectedItems() {
        self.setTrashedToSelectedItems(trashed: true)
    }

    func restoreSelectedItems() {
        self.setTrashedToSelectedItems(trashed: false)
    }

    func deleteSelectedItems() {
        do {
            let request = DeleteObjectsDbRequest<RItem>(keys: Array(self.state.selectedItems),
                                                        libraryId: self.state.library.identifier)
            try self.dbStorage.createCoordinator().perform(request: request)
        } catch let error {
            DDLogError("ItemsStore: can't delete items - \(error)")
            self.state.error = .deletion
        }
    }

    private func setTrashedToSelectedItems(trashed: Bool) {
        do {
            let request = MarkItemsAsTrashedDbRequest(keys: Array(self.state.selectedItems),
                                                      libraryId: self.state.library.identifier,
                                                      trashed: trashed)
            try self.dbStorage.createCoordinator().perform(request: request)
        } catch let error {
            DDLogError("ItemsStore: can't trash items - \(error)")
            self.state.error = .deletion
        }
    }

    private class func request(for type: State.ItemType, libraryId: LibraryIdentifier) -> ReadItemsDbRequest {
        let request: ReadItemsDbRequest
        switch type {
        case .all:
            request = ReadItemsDbRequest(libraryId: libraryId,
                                         collectionKey: nil, parentKey: "", trash: false)
        case .trash:
            request = ReadItemsDbRequest(libraryId: libraryId,
                                         collectionKey: nil, parentKey: nil, trash: true)
        case .publications, .search:
            // TODO: - implement publications and search fetching
            request = ReadItemsDbRequest(libraryId: .group(-1),
                                         collectionKey: nil, parentKey: nil, trash: true)
        case .collection(let key, _):
            request = ReadItemsDbRequest(libraryId: libraryId,
                                         collectionKey: key, parentKey: "", trash: false)
        }
        return request
    }

    private class func sections(from results: Results<RItem>, sortType: ItemsSortType) -> [String] {
        let sortedResults = results.sorted(by: sortType.descriptors)

        switch sortType.field {
        case .title:
            return Set(sortedResults.map({ $0.title.first.flatMap(String.init)?.uppercased() ?? "-" }))
                        .sorted(by: {
                            comparator(for: sortType, left: $0, right: $1)
                        })
        }
    }

    private class func comparator(for sortType: ItemsSortType, left: String, right: String) -> Bool {
        return sortType.ascending ? left < right : left > right
    }
}
