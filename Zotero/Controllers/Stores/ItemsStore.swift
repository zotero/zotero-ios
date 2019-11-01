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
        case dataLoading, deletion, collectionAssignment, itemMove, noteSaving, attachmentAdding
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

        fileprivate(set) var results: Results<RItem>? {
            didSet {
                self.resultsDidChange?()
            }
        }
        fileprivate var unfilteredResults: Results<RItem>?
        var error: Error?
        var sortType: ItemsSortType {
            willSet {
                self.results = self.results?.sorted(by: newValue.descriptors)
                self.unfilteredResults = self.unfilteredResults?.sorted(by: newValue.descriptors)
            }
        }
        var selectedItems: Set<String> = []
        var showingCreation: Bool = false
        var resultsDidChange: (() -> Void)?
    }

    @Published var state: State
    private let dbStorage: DbStorage
    private let fileStorage: FileStorage

    init(type: State.ItemType, library: Library, dbStorage: DbStorage, fileStorage: FileStorage) {
        self.dbStorage = dbStorage
        self.fileStorage = fileStorage

        do {
            let sortType = ItemsSortType(field: .title, ascending: true)
            let items = try dbStorage.createCoordinator()
                                     .perform(request: ItemsStore.request(for: type, libraryId: library.identifier))
                                     .sorted(by: sortType.descriptors)

            self.state = State(type: type,
                               library: library,
                               results: items,
                               sortType: sortType)
        } catch let error {
            DDLogError("ItemStore: can't load items - \(error)")
            self.state = State(type: type,
                               library: library,
                               error: .dataLoading,
                               sortType: ItemsSortType(field: .title, ascending: true))
        }
    }

    // MARK: - Actions

    func moveItems(with keys: [String], to key: String) {
        let request = MoveItemsToParentDbRequest(itemKeys: keys, parentKey: key, libraryId: self.state.library.identifier)
        self.perform(request: request) { [weak self] error in
            DDLogError("ItemsStore: can't move items to parent: \(error)")
            self?.state.error = .itemMove
        }
    }

    func search(for text: String) {
        if text.isEmpty {
            self.removeResultsFilters()
        } else {
            self.filterResults(with: text)
        }
    }

    private func filterResults(with text: String) {
        if self.state.unfilteredResults == nil {
            self.state.unfilteredResults = self.state.results
        }
        self.state.results = self.state.unfilteredResults?.filter(.itemSearch(for: text))
    }

    private func removeResultsFilters() {
        guard self.state.unfilteredResults != nil else { return }
        self.state.results = self.state.unfilteredResults
        self.state.unfilteredResults = nil
    }

    func addAttachments(from urls: [URL]) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let `self` = self else { return }

            let attachments = urls.map({ Files.file(from: $0) })
                                  .map({
                                    ItemDetailStore.State.Attachment(key: KeyGenerator.newKey,
                                                                     title: $0.name,
                                                                     type: .file(file: $0, filename: $0.name, isLocal: true),
                                                                     libraryId: self.state.library.identifier)
                                  })

            do {
                try self.fileStorage.copyAttachmentFilesIfNeeded(for: attachments)

                for attachment in attachments {
                    let request = CreateAttachmentDbRequest(attachment: attachment, libraryId: self.state.library.identifier)
                    _ = try self.dbStorage.createCoordinator().perform(request: request)
                }
            } catch let error {
                DispatchQueue.main.async { [weak self] in
                    DDLogError("ItemsStore: can't add attachment: \(error)")
                    self?.state.error = .attachmentAdding
                }
            }
        }
    }

    func saveNewNote(with text: String) {
        let note = ItemDetailStore.State.Note(key: KeyGenerator.newKey, text: text)
        let request = CreateNoteDbRequest(note: note, libraryId: self.state.library.identifier)
        self.perform(request: request) { [weak self] error in
            DDLogError("ItemsStore: can't save new note: \(error)")
            self?.state.error = .noteSaving
        }
    }

    func saveChanges(for note: ItemDetailStore.State.Note) {
        let request = StoreNoteDbRequest(note: note, libraryId: self.state.library.identifier)
        self.perform(request: request) { [weak self] error in
            DDLogError("ItemsStore: can't save note: \(error)")
            self?.state.error = .noteSaving
        }
    }

    @objc func removeSelectedItemsFromCollection() {
        guard let collectionKey = self.state.type.collectionKey else { return }
        let request = DeleteItemsFromCollectionDbRequest(collectionKey: collectionKey,
                                                        itemKeys: self.state.selectedItems,
                                                        libraryId: self.state.library.identifier)
        self.perform(request: request) { [weak self] error in
            DDLogError("ItemsStore: can't assign collections to items - \(error)")
            self?.state.error = .collectionAssignment
        }
    }

    func assignSelectedItems(to collectionKeys: Set<String>) {
        let request = AssignItemsToCollectionsDbRequest(collectionKeys: collectionKeys,
                                                        itemKeys: self.state.selectedItems,
                                                        libraryId: self.state.library.identifier)
        self.perform(request: request) { [weak self] error in
            DDLogError("ItemsStore: can't assign collections to items - \(error)")
            self?.state.error = .collectionAssignment
        }
    }

    @objc func trashSelectedItems() {
        self.setTrashedToSelectedItems(trashed: true)
    }

    @objc func restoreSelectedItems() {
        self.setTrashedToSelectedItems(trashed: false)
    }

    @objc func deleteSelectedItems() {
        let request = DeleteObjectsDbRequest<RItem>(keys: Array(self.state.selectedItems),
                                                    libraryId: self.state.library.identifier)
        self.perform(request: request) { [weak self] error in
            DDLogError("ItemsStore: can't delete items - \(error)")
            self?.state.error = .deletion
        }
    }

    private func setTrashedToSelectedItems(trashed: Bool) {
        let request = MarkItemsAsTrashedDbRequest(keys: Array(self.state.selectedItems),
                                                  libraryId: self.state.library.identifier,
                                                  trashed: trashed)
        self.perform(request: request) { [weak self] error in
            DDLogError("ItemsStore: can't trash items - \(error)")
            self?.state.error = .deletion
        }
    }

    // MARK: - Helpers

    private func perform<Request: DbResponseRequest>(request: Request, errorAction: @escaping (Swift.Error) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                _ = try self?.dbStorage.createCoordinator().perform(request: request)
            } catch let error {
                DispatchQueue.main.async {
                    errorAction(error)
                }
            }
        }
    }

    private func perform<Request: DbRequest>(request: Request, errorAction: @escaping (Swift.Error) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try self?.dbStorage.createCoordinator().perform(request: request)
            } catch let error {
                DispatchQueue.main.async {
                    errorAction(error)
                }
            }
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
}
