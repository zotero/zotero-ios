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

final class CollectionsActionHandler: ViewModelActionHandler, BackgroundDbProcessingActionHandler {
    typealias Action = CollectionsAction
    typealias State = CollectionsState

    let backgroundQueue: DispatchQueue
    private unowned let fileStorage: FileStorage
    unowned let dbStorage: DbStorage
    private unowned let attachmentDownloader: AttachmentDownloader
    private unowned let fileCleanupController: AttachmentFileCleanupController

    init(dbStorage: DbStorage, fileStorage: FileStorage, attachmentDownloader: AttachmentDownloader, fileCleanupController: AttachmentFileCleanupController) {
        backgroundQueue = DispatchQueue(label: "org.zotero.CollectionsActionHandler.backgroundQueue", qos: .userInitiated)
        self.dbStorage = dbStorage
        self.fileStorage = fileStorage
        self.attachmentDownloader = attachmentDownloader
        self.fileCleanupController = fileCleanupController
    }

    func process(action: CollectionsAction, in viewModel: ViewModel<CollectionsActionHandler>) {
        switch action {
        case .startEditing(let type):
            startEditing(type: type, in: viewModel)

        case .assignKeysToCollection(let fromKeys, let toKey):
            assignItems(keys: fromKeys, to: toKey, in: viewModel)

        case .deleteCollection(let key):
            delete(object: RCollection.self, keys: [key], in: viewModel)

        case .deleteSearch(let key):
            delete(object: RSearch.self, keys: [key], in: viewModel)

        case .select(let collectionId):
            update(viewModel: viewModel) { state in
                state.selectedCollectionId = collectionId
                state.changes.insert(.selection)
            }

        case .loadData:
            loadData(in: viewModel)

        case .toggleCollapsed(let collection):
            toggleCollapsed(for: collection, in: viewModel)

        case .emptyTrash:
            emptyTrash(in: viewModel)

        case .expandAll(let selectedCollectionIsRoot):
            set(allCollapsed: false, selectedCollectionIsRoot: selectedCollectionIsRoot, in: viewModel)

        case .collapseAll(let selectedCollectionIsRoot):
            set(allCollapsed: true, selectedCollectionIsRoot: selectedCollectionIsRoot, in: viewModel)

        case .loadItemKeysForBibliography(let collection):
            loadItemKeysForBibliography(collection: collection, in: viewModel)

        case .downloadAttachments(let identifier):
            downloadAttachments(in: identifier, viewModel: viewModel)

        case .removeDownloads(let identifier):
            removeDownloads(in: identifier, viewModel: viewModel)
        }
    }

    private func downloadAttachments(in collectionId: CollectionIdentifier, viewModel: ViewModel<CollectionsActionHandler>) {
        backgroundQueue.async { [weak self, weak viewModel] in
            guard let self, let viewModel else { return }
            do {
                let items = try dbStorage.perform(request: ReadAllAttachmentsFromCollectionDbRequest(collectionId: collectionId, libraryId: viewModel.state.library.identifier), on: backgroundQueue)
                let fileStorage = self.fileStorage
                let attachments = items.compactMap({ item -> (Attachment, String?)? in
                    guard let attachment = AttachmentCreator.attachment(for: item, fileStorage: fileStorage, urlDetector: nil) else { return nil }

                    switch attachment.type {
                    case .file(_, _, _, let linkType, _):
                        switch linkType {
                        case .importedFile, .importedUrl:
                            return (attachment, item.parent?.key)

                        default:
                            break
                        }

                    default:
                        break
                    }

                    return nil
                })
                attachmentDownloader.batchDownload(attachments: Array(attachments))
            } catch let error {
                DDLogError("CollectionsActionHandler: download attachments - \(error)")
            }
        }
    }

    private func removeDownloads(in collectionId: CollectionIdentifier, viewModel: ViewModel<CollectionsActionHandler>) {
        backgroundQueue.async { [weak self, weak viewModel] in
            guard let self, let viewModel else { return }
            do {
                let items = try dbStorage.perform(request: ReadItemsDbRequest(collectionId: collectionId, libraryId: viewModel.state.library.identifier), on: backgroundQueue)
                let keys = Set(items.map { $0.key })
                fileCleanupController.delete(.allForItems(keys, viewModel.state.library.identifier))
            } catch let error {
                DDLogError("CollectionsActionHandler: remove downloads - \(error)")
            }
        }
    }

    private func emptyTrash(in viewModel: ViewModel<CollectionsActionHandler>) {
        perform(request: EmptyTrashDbRequest(libraryId: viewModel.state.library.identifier)) { error in
            guard let error else { return }
            DDLogError("CollectionsActionHandler: can't empty trash - \(error)")
            // TODO: - show error
        }
    }

    private func loadItemKeysForBibliography(collection: Collection, in viewModel: ViewModel<CollectionsActionHandler>) {
        do {
            let items = try dbStorage.perform(request: ReadItemsDbRequest(collectionId: collection.identifier, libraryId: viewModel.state.library.identifier), on: .main)
            let keys = Set(items.map({ $0.key }))
            update(viewModel: viewModel) { state in
                state.itemKeysForBibliography = .success(keys)
            }
        } catch let error {
            DDLogError("CollectionsActionHandler: can't load bibliography items - \(error)")
            update(viewModel: viewModel) { state in
                state.itemKeysForBibliography = .failure(error)
            }
        }
    }

    private func set(allCollapsed: Bool, selectedCollectionIsRoot: Bool, in viewModel: ViewModel<CollectionsActionHandler>) {
        var changedCollections: Set<CollectionIdentifier> = []

        update(viewModel: viewModel) { state in
            changedCollections = state.collectionTree.setAll(collapsed: allCollapsed)
            state.changes = .collapsedState

            if allCollapsed && !state.collectionTree.isRoot(identifier: state.selectedCollectionId) {
                state.selectedCollectionId = .custom(.all)
                state.changes.insert(.selection)
            }
        }

        let request = SetCollectionsCollapsedDbRequest(identifiers: changedCollections, collapsed: allCollapsed, libraryId: viewModel.state.library.identifier)
        perform(request: request) { error in
            guard let error else { return }
            DDLogError("CollectionsActionHandler: can't change collapsed all - \(error)")
        }
    }

    private func toggleCollapsed(for collection: Collection, in viewModel: ViewModel<CollectionsActionHandler>) {
        guard let collapsed = viewModel.state.collectionTree.isCollapsed(identifier: collection.identifier) else { return }

        let newCollapsed = !collapsed
        let libraryId = viewModel.state.library.identifier

        // Update local state
        update(viewModel: viewModel) { state in
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
        perform(request: request) { error in
            guard let error else { return }
            DDLogError("CollectionsActionHandler: can't change collapsed - \(error)")
            // TODO: show error
        }
    }

    private func loadData(in viewModel: ViewModel<CollectionsActionHandler>) {
        let includeItemCounts = Defaults.shared.showCollectionItemCounts
        let libraryId = viewModel.state.library.identifier

        do {
            try dbStorage.perform(on: .main, with: { [weak self, weak viewModel] coordinator in
                guard let self, let viewModel else { return }
                let collections = try coordinator.perform(request: ReadCollectionsDbRequest(libraryId: libraryId))
                let (library, libraryToken) = try libraryId.observe(in: coordinator, changes: { [weak self, weak viewModel] library in
                    guard let self, let viewModel else { return }
                    update(viewModel: viewModel) { state in
                        state.library = library
                        state.changes = .library
                    }
                })

                var allItemCount = 0
                var unfiledItemCount = 0
                var trashItemCount = 0
                var itemsToken: NotificationToken?
                var unfiledToken: NotificationToken?
                var trashItemsToken: NotificationToken?
                var trashCollectionsToken: NotificationToken?

                if includeItemCounts {
                    let allItems = try coordinator.perform(request: ReadItemsDbRequest(collectionId: .custom(.all), libraryId: libraryId))
                    allItemCount = allItems.count

                    let unfiledItems = try coordinator.perform(request: ReadItemsDbRequest(collectionId: .custom(.unfiled), libraryId: libraryId))
                    unfiledItemCount = unfiledItems.count

                    let trashItems = try coordinator.perform(request: ReadItemsDbRequest(collectionId: .custom(.trash), libraryId: libraryId))
                    let trashCollections = try coordinator.perform(request: ReadCollectionsDbRequest(libraryId: libraryId, trash: true))
                    trashItemCount = trashItems.count + trashCollections.count

                    itemsToken = observeItemCount(in: allItems, for: .all, in: viewModel, handler: self)
                    unfiledToken = observeItemCount(in: unfiledItems, for: .unfiled, in: viewModel, handler: self)
                    trashItemsToken = observeItemCount(in: trashItems, for: .trash, in: viewModel, handler: self)
                    trashCollectionsToken = observeTrashedCollectionCount(in: trashCollections, in: viewModel, handler: self)
                }

                let collectionTree = CollectionTreeBuilder.collections(from: collections, libraryId: libraryId, includeItemCounts: includeItemCounts)
                collectionTree.insert(collection: Collection(custom: .all, itemCount: allItemCount), at: 0)
                collectionTree.append(collection: Collection(custom: .unfiled, itemCount: unfiledItemCount))
                collectionTree.append(collection: Collection(custom: .trash, itemCount: trashItemCount))

                let collectionsToken = collections.observe(keyPaths: RCollection.observableKeypathsForList, { [weak self, weak viewModel] changes in
                    guard let self, let viewModel else { return }
                    switch changes {
                    case .update(let objects, _, _, _):
                        updateCollections(with: objects.freeze(), includeItemCounts: includeItemCounts, in: viewModel, handler: self)

                    case .initial, .error:
                        break
                    }
                })

                update(viewModel: viewModel) { state in
                    state.collectionTree = collectionTree
                    state.library = library
                    state.libraryToken = libraryToken
                    state.collectionsToken = collectionsToken
                    state.itemsToken = itemsToken
                    state.unfiledToken = unfiledToken
                    state.trashItemsToken = trashItemsToken
                    state.trashCollectionsToken = trashCollectionsToken
                }
            })
        } catch let error {
            DDLogError("CollectionsActionHandlers: can't load data - \(error)")
            update(viewModel: viewModel) { state in
                state.error = .dataLoading
            }
        }

        func observeItemCount(
            in results: Results<RItem>,
            for customType: CollectionIdentifier.CustomType,
            in viewModel: ViewModel<CollectionsActionHandler>,
            handler: CollectionsActionHandler
        ) -> NotificationToken {
            return results.observe({ [weak handler, weak viewModel] changes in
                guard let handler, let viewModel else { return }
                switch changes {
                case .update(let objects, _, _, _):
                    let itemsCount = objects.freeze().count
                    switch customType {
                    case .trash:
                        updateTrashCount(itemsCount: itemsCount, collectionsCount: nil, in: viewModel, handler: handler)

                    case .all, .publications, .unfiled:
                        updateItemsCount(itemsCount, for: customType, in: viewModel, handler: handler)
                    }

                case .initial:
                    break

                case .error:
                    break
                }
            })

            func updateItemsCount(_ count: Int, for customType: CollectionIdentifier.CustomType, in viewModel: ViewModel<CollectionsActionHandler>, handler: CollectionsActionHandler) {
                handler.update(viewModel: viewModel) { state in
                    state.collectionTree.update(collection: Collection(custom: customType, itemCount: count))

                    switch customType {
                    case .all:
                        state.changes = .allItemCount

                    case .unfiled:
                        state.changes = .unfiledItemCount

                    case .trash:
                        state.changes = .trashItemCount

                    case .publications:
                        break
                    }
                }
            }
        }

        func observeTrashedCollectionCount(in results: Results<RCollection>, in viewModel: ViewModel<CollectionsActionHandler>, handler: CollectionsActionHandler) -> NotificationToken {
            return results.observe({ [weak handler, weak viewModel] changes in
                guard let handler, let viewModel else { return }
                switch changes {
                case .update(let objects, _, _, _):
                    let collectionsCount = objects.freeze().count
                    updateTrashCount(itemsCount: nil, collectionsCount: collectionsCount, in: viewModel, handler: handler)

                case .initial:
                    break

                case .error:
                    break
                }
            })
        }

        func updateTrashCount(itemsCount: Int?, collectionsCount: Int?, in viewModel: ViewModel<CollectionsActionHandler>, handler: CollectionsActionHandler) {
            var count = 0
            if let itemsCount {
                count += itemsCount
            } else {
                count += (try? handler.dbStorage.perform(request: ReadItemsDbRequest(collectionId: .custom(.trash), libraryId: libraryId), on: .main))?.count ?? 0
            }
            if let collectionsCount {
                count += collectionsCount
            } else {
                count += (try? handler.dbStorage.perform(request: ReadCollectionsDbRequest(libraryId: libraryId, trash: true), on: .main))?.count ?? 0
            }
            handler.update(viewModel: viewModel) { state in
                state.collectionTree.update(collection: Collection(custom: .trash, itemCount: count))
                state.changes = .trashItemCount
            }
        }

        func updateCollections(with collections: Results<RCollection>, includeItemCounts: Bool, in viewModel: ViewModel<CollectionsActionHandler>, handler: CollectionsActionHandler) {
            let tree = CollectionTreeBuilder.collections(from: collections, libraryId: viewModel.state.library.identifier, includeItemCounts: includeItemCounts)

            handler.update(viewModel: viewModel) { state in
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

    private func assignItems(keys: Set<String>, to collectionKey: String, in viewModel: ViewModel<CollectionsActionHandler>) {
        let collectionKeys: Set<String> = [collectionKey]
        let request = AssignItemsToCollectionsDbRequest(collectionKeys: collectionKeys, itemKeys: keys, libraryId: viewModel.state.library.identifier)
        perform(request: request) { [weak self, weak viewModel] error in
            guard let error, let self, let viewModel else { return }

            DDLogError("CollectionsActionHandler: can't assign collections to items - \(error)")

            update(viewModel: viewModel) { state in
                state.error = .collectionAssignment
            }
        }
    }

    private func delete<Obj: DeletableObject&Updatable>(object: Obj.Type, keys: [String], in viewModel: ViewModel<CollectionsActionHandler>) {
        let request = MarkCollectionsAsTrashedDbRequest(keys: keys, libraryId: viewModel.state.library.identifier, trashed: true)
        perform(request: request) { [weak self, weak viewModel] error in
            guard let error, let self, let viewModel else { return }
            DDLogError("CollectionsActionHandler: can't delete object - \(error)")
            update(viewModel: viewModel) { state in
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
                let request = ReadRCollectionDbRequest(libraryId: viewModel.state.library.identifier, key: parentKey)
                let rCollection = try? dbStorage.perform(request: request, on: .main)
                parent = rCollection.flatMap { Collection(object: $0, itemCount: 0) }
            } else {
                parent = nil
            }
        }

        update(viewModel: viewModel) { state in
            state.editingData = (key, name, parent)
        }
    }
}
