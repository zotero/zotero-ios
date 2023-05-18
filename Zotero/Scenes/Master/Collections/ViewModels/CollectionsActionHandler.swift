//
//  CollectionsActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 24/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RealmSwift

struct CollectionsActionHandler: ViewModelActionHandler, BackgroundDbProcessingActionHandler {
    typealias Action = CollectionsAction
    typealias State = CollectionsState

    let backgroundQueue: DispatchQueue
    private unowned let fileStorage: FileStorage
    unowned let dbStorage: DbStorage
    private unowned let attachmentDownloader: AttachmentDownloader

    init(dbStorage: DbStorage, fileStorage: FileStorage, attachmentDownloader: AttachmentDownloader) {
        self.backgroundQueue = DispatchQueue(label: "org.zotero.CollectionsActionHandler.backgroundQueue", qos: .userInitiated)
        self.dbStorage = dbStorage
        self.fileStorage = fileStorage
        self.attachmentDownloader = attachmentDownloader
    }

    func process(action: CollectionsAction, in viewModel: ViewModel<CollectionsActionHandler>) {
        switch action {
        case .startEditing(let type):
            self.startEditing(type: type, in: viewModel)

        case .assignKeysToCollection(let fromKeys, let toKey):
            self.assignItems(keys: fromKeys, to: toKey, in: viewModel)

        case .deleteCollection(let key):
            self.delete(object: RCollection.self, keys: [key], in: viewModel)

        case .deleteSearch(let key):
            self.delete(object: RSearch.self, keys: [key], in: viewModel)

        case .select(let collectionId):
            self.update(viewModel: viewModel) { state in
                state.selectedCollectionId = collectionId
                state.changes.insert(.selection)
            }

        case .loadData:
            self.loadData(in: viewModel)

        case .toggleCollapsed(let collection):
            self.toggleCollapsed(for: collection, in: viewModel)

        case .emptyTrash:
            self.emptyTrash(in: viewModel)

        case .expandAll(let selectedCollectionIsRoot):
            self.set(allCollapsed: false, selectedCollectionIsRoot: selectedCollectionIsRoot, in: viewModel)

        case .collapseAll(let selectedCollectionIsRoot):
            self.set(allCollapsed: true, selectedCollectionIsRoot: selectedCollectionIsRoot, in: viewModel)

        case .loadItemKeysForBibliography(let collection):
            self.loadItemKeysForBibliography(collection: collection, in: viewModel)

        case .downloadAttachments(let identifier):
            self.downloadAttachments(in: identifier, viewModel: viewModel)
        }
    }

    private func downloadAttachments(in collectionId: CollectionIdentifier, viewModel: ViewModel<CollectionsActionHandler>) {
        self.backgroundQueue.async { [weak viewModel] in
            guard let viewModel = viewModel else { return }
            self._downloadAttachments(in: collectionId, viewModel: viewModel)
        }
    }

    private func _downloadAttachments(in collectionId: CollectionIdentifier, viewModel: ViewModel<CollectionsActionHandler>) {
        do {
            let items = try self.dbStorage.perform(request: ReadAllAttachmentsFromCollectionDbRequest(collectionId: collectionId, libraryId: viewModel.state.libraryId), on: self.backgroundQueue)
            let attachments = items.compactMap({ item -> (Attachment, String?)? in
                guard let attachment = AttachmentCreator.attachment(for: item, fileStorage: self.fileStorage, urlDetector: nil) else { return nil }

                switch attachment.type {
                case .file(_, _, _, let linkType):
                    switch linkType {
                    case .importedFile, .importedUrl:
                        return (attachment, item.parent?.key)
                    default: break
                    }
                default: break
                }

                return nil
            })
            self.attachmentDownloader.batchDownload(attachments: Array(attachments))
        } catch let error {
            DDLogError("CollectionsActionHandler: download attachments - \(error)")
        }
    }

    private func emptyTrash(in viewModel: ViewModel<CollectionsActionHandler>) {
        self.perform(request: EmptyTrashDbRequest(libraryId: viewModel.state.libraryId)) { error in
            guard let error = error else { return }
            DDLogError("CollectionsActionHandler: can't empty trash - \(error)")
            // TODO: - show error
        }
    }

    private func loadItemKeysForBibliography(collection: Collection, in viewModel: ViewModel<CollectionsActionHandler>) {
        do {
            let items = try self.dbStorage.perform(request: ReadItemsDbRequest(collectionId: collection.identifier, libraryId: viewModel.state.libraryId), on: .main)
            let keys = Set(items.map({ $0.key }))
            self.update(viewModel: viewModel) { state in
                state.itemKeysForBibliography = .success(keys)
            }
        } catch let error {
            DDLogError("CollectionsActionHandler: can't load bibliography items - \(error)")
            self.update(viewModel: viewModel) { state in
                state.itemKeysForBibliography = .failure(error)
            }
        }
    }

    private func set(allCollapsed: Bool, selectedCollectionIsRoot: Bool, in viewModel: ViewModel<CollectionsActionHandler>) {
        var changedCollections: Set<CollectionIdentifier> = []

        self.update(viewModel: viewModel) { state in
            changedCollections = state.collectionTree.setAll(collapsed: allCollapsed)
            state.changes = .collapsedState

            if allCollapsed && !state.collectionTree.isRoot(identifier: state.selectedCollectionId) {
                state.selectedCollectionId = .custom(.all)
                state.changes.insert(.selection)
            }
        }

        let request = SetCollectionsCollapsedDbRequest(identifiers: changedCollections, collapsed: allCollapsed, libraryId: viewModel.state.libraryId)
        self.perform(request: request) { error in
            guard let error = error else { return }
            DDLogError("CollectionsActionHandler: can't change collapsed all - \(error)")
        }
    }

    private func toggleCollapsed(for collection: Collection, in viewModel: ViewModel<CollectionsActionHandler>) {
        guard let collapsed = viewModel.state.collectionTree.isCollapsed(identifier: collection.identifier) else { return }

        let newCollapsed = !collapsed
        let libraryId = viewModel.state.library.identifier

        // Update local state
        self.update(viewModel: viewModel) { state in
            state.collectionTree.set(collapsed: newCollapsed, to: collection.identifier)
            state.changes = .collapsedState

            // If a collection is being collapsed and selected collection is a child of collapsed collection, select currently collapsed collection
            if state.selectedCollectionId != collection.identifier && newCollapsed && !state.collectionTree.isRoot(identifier: state.selectedCollectionId) &&
               state.collectionTree.identifier(state.selectedCollectionId, isChildOf: collection.identifier) {
                state.selectedCollectionId = collection.identifier
                state.changes.insert(.selection)
            }
        }

        // Store change to database
        let request = SetCollectionCollapsedDbRequest(collapsed: !collapsed, identifier: collection.identifier, libraryId: libraryId)
        self.perform(request: request) { error in
            guard let error = error else { return }
            DDLogError("CollectionsActionHandler: can't change collapsed - \(error)")
            // TODO: show error
        }
    }

    private func child(of collectionId: CollectionIdentifier, containsSelectedId selectedId: CollectionIdentifier, in childCollections: [CollectionIdentifier: [CollectionIdentifier]]) -> Bool {
        guard let children = childCollections[collectionId] else { return false }

        if children.contains(selectedId) {
            return true
        }

        for childId in children {
            if self.child(of: childId, containsSelectedId: selectedId, in: childCollections) {
                return true
            }
        }

        return false
    }

    private func loadData(in viewModel: ViewModel<CollectionsActionHandler>) {
        let libraryId = viewModel.state.libraryId
        let includeItemCounts = Defaults.shared.showCollectionItemCounts

        do {
            try self.dbStorage.perform(on: .main, with: { coordinator in
                let library = try coordinator.perform(request: ReadLibraryDbRequest(libraryId: libraryId))
                let collections = try coordinator.perform(request: ReadCollectionsDbRequest(libraryId: libraryId))

                var allItemCount = 0
                var unfiledItemCount = 0
                var trashItemCount = 0
                var itemsToken: NotificationToken?
                var unfiledToken: NotificationToken?
                var trashToken: NotificationToken?

                if includeItemCounts {
                    let allItems = try coordinator.perform(request: ReadItemsDbRequest(collectionId: .custom(.all), libraryId: libraryId))
                    allItemCount = allItems.count

                    let unfiledItems = try coordinator.perform(request: ReadItemsDbRequest(collectionId: .custom(.unfiled), libraryId: libraryId))
                    unfiledItemCount = unfiledItems.count

                    let trashItems = try coordinator.perform(request: ReadItemsDbRequest(collectionId: .custom(.trash), libraryId: libraryId))
                    trashItemCount = trashItems.count

                    itemsToken = self.observeItemCount(in: allItems, for: .all, in: viewModel)
                    unfiledToken = self.observeItemCount(in: unfiledItems, for: .unfiled, in: viewModel)
                    trashToken = self.observeItemCount(in: trashItems, for: .trash, in: viewModel)
                }

                let collectionTree = CollectionTreeBuilder.collections(from: collections, libraryId: libraryId, includeItemCounts: includeItemCounts)
                collectionTree.insert(collection: Collection(custom: .all, itemCount: allItemCount), at: 0)
                collectionTree.append(collection: Collection(custom: .unfiled, itemCount: unfiledItemCount))
                collectionTree.append(collection: Collection(custom: .trash, itemCount: trashItemCount))

                let collectionsToken = collections.observe(keyPaths: RCollection.observableKeypathsForList, { [weak viewModel] changes in
                    guard let viewModel = viewModel else { return }
                    switch changes {
                    case .update(let objects, _, _, _): self.update(collections: objects, includeItemCounts: includeItemCounts, viewModel: viewModel)
                    case .initial: break
                    case .error: break
                    }
                })

                self.update(viewModel: viewModel) { state in
                    state.collectionTree = collectionTree
                    state.library = library
                    state.collectionsToken = collectionsToken
                    state.itemsToken = itemsToken
                    state.unfiledToken = unfiledToken
                    state.trashToken = trashToken
                }
            })
        } catch let error {
            DDLogError("CollectionsActionHandlers: can't load data - \(error)")
            self.update(viewModel: viewModel) { state in
                state.error = .dataLoading
            }
        }
    }

    private func assignItems(keys: Set<String>, to collectionKey: String, in viewModel: ViewModel<CollectionsActionHandler>) {
        let collectionKeys: Set<String> = [collectionKey]
        let request = AssignItemsToCollectionsDbRequest(collectionKeys: collectionKeys, itemKeys: keys, libraryId: viewModel.state.library.identifier)
        self.perform(request: request) { [weak viewModel] error in
            guard let error = error, let viewModel = viewModel else { return }

            DDLogError("CollectionsActionHandler: can't assign collections to items - \(error)")

            self.update(viewModel: viewModel) { state in
                state.error = .collectionAssignment
            }
        }
    }

    private func delete<Obj: DeletableObject&Updatable>(object: Obj.Type, keys: [String], in viewModel: ViewModel<CollectionsActionHandler>) {
        let request = MarkObjectsAsDeletedDbRequest<Obj>(keys: keys, libraryId: viewModel.state.library.identifier)
        self.perform(request: request) { [weak viewModel] error in
            guard let error = error, let viewModel = viewModel else { return }

            DDLogError("CollectionsActionHandler: can't delete object - \(error)")

            self.update(viewModel: viewModel) { state in
                state.error = .deletion
            }
        }
    }

    /// Loads data needed to show editing controller.
    /// - parameter type: Editing type.
    private func startEditing(type: CollectionsState.EditingType, in viewModel: ViewModel<CollectionsActionHandler>) {
        let key: String?
        let name: String
        let parent: Collection?

        switch type {
        case .add:
            key = nil
            name = ""
            parent = nil

        case .addSubcollection(let collection):
            key = nil
            name = ""
            parent = collection

        case .edit(let collection):
            key = collection.identifier.key
            name = collection.name

            if let parentKey = viewModel.state.collectionTree.parent(of: collection.identifier)?.key {
                let request = ReadCollectionDbRequest(libraryId: viewModel.state.library.identifier, key: parentKey)
                let rCollection = try? self.dbStorage.perform(request: request, on: .main)
                parent = rCollection.flatMap { Collection(object: $0, itemCount: 0) }
            } else {
                parent = nil
            }
        }


        self.update(viewModel: viewModel) { state in
            state.editingData = (key, name, parent)
        }
    }

    private func observeItemCount(in results: Results<RItem>, for customType: CollectionIdentifier.CustomType, in viewModel: ViewModel<CollectionsActionHandler>) -> NotificationToken {
        return results.observe({ [weak viewModel] changes in
            guard let viewModel = viewModel else { return }
            switch changes {
            case .update(let objects, _, _, _):
                self.update(itemsCount: objects.count, for: customType, in: viewModel)
            case .initial: break
            case .error: break
            }
        })
    }

    private func update(itemsCount: Int, for customType: CollectionIdentifier.CustomType, in viewModel: ViewModel<CollectionsActionHandler>) {
        self.update(viewModel: viewModel) { state in
            state.collectionTree.update(collection: Collection(custom: customType, itemCount: itemsCount))

            switch customType {
            case .all:
                state.changes = .allItemCount
            case .unfiled:
                state.changes = .unfiledItemCount
            case .trash:
                state.changes = .trashItemCount
            case .publications: break
            }
        }
    }

    private func update(collections: Results<RCollection>, includeItemCounts: Bool, viewModel: ViewModel<CollectionsActionHandler>) {
        let tree = CollectionTreeBuilder.collections(from: collections, libraryId: viewModel.state.libraryId, includeItemCounts: includeItemCounts)

        self.update(viewModel: viewModel) { state in
            state.collectionTree.replace(identifiersMatching: { $0.isCollection }, with: tree)
            state.changes = .results

            // Check whether selection still exists
            if state.collectionTree.collection(for: state.selectedCollectionId) == nil {
                state.selectedCollectionId = .custom(.all)
                state.changes.insert(.selection)
            }
        }
    }
}
