//
//  ItemsViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 20.09.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import UIKit
import SwiftUI

import CocoaLumberjackSwift
import RealmSwift
import RxSwift
import WebKit

final class ItemsViewController: BaseItemsViewController {
    private let viewModel: ViewModel<ItemsActionHandler>

    private var dataSource: RItemsTableViewDataSource!
    private var resultsToken: NotificationToken?
    private var libraryToken: NotificationToken?
    override var library: Library {
        return viewModel.state.library
    }
    override var collection: Collection {
        return viewModel.state.collection
    }
    override var toolbarData: ItemsToolbarController.Data {
        return toolbarData(from: viewModel.state)
    }

    init(viewModel: ViewModel<ItemsActionHandler>, controllers: Controllers, coordinatorDelegate: (DetailItemsCoordinatorDelegate & DetailNoteEditorCoordinatorDelegate)) {
        self.viewModel = viewModel
        super.init(controllers: controllers, coordinatorDelegate: coordinatorDelegate)
        viewModel.process(action: .loadInitialState)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        dataSource = RItemsTableViewDataSource(
            viewModel: viewModel,
            fileDownloader: controllers.userControllers?.fileDownloader,
            recognizerController: controllers.userControllers?.recognizerController,
            schemaController: controllers.schemaController
        )
        handler = ItemsTableViewHandler(tableView: tableView, delegate: self, dataSource: dataSource, dragDropController: controllers.dragDropController)
        toolbarController = ItemsToolbarController(viewController: self, data: toolbarData, collection: collection, library: library, delegate: self)
        setupRightBarButtonItems(expectedItems: rightBarButtonItemTypes(for: viewModel.state))
        setupFileObservers()
        setupRecognizerObserver()
        setupAppStateObserver()

        if let term = viewModel.state.searchTerm, !term.isEmpty {
            navigationItem.searchController?.searchBar.text = term
        }
        if let results = viewModel.state.results {
            startObserving(results: results)
        }

        viewModel
            .stateObservable
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] state in
                self?.update(state: state)
            })
            .disposed(by: disposeBag)

        func setupFileObservers() {
            NotificationCenter.default
                .rx
                .notification(.attachmentFileDeleted)
                .observe(on: MainScheduler.instance)
                .subscribe(onNext: { [weak self] notification in
                    if let notification = notification.object as? AttachmentFileDeletedNotification {
                        self?.viewModel.process(action: .updateAttachments(notification))
                    }
                })
                .disposed(by: disposeBag)

            let downloader = controllers.userControllers?.fileDownloader
            downloader?.observable
                .observe(on: MainScheduler.asyncInstance)
                .subscribe(onNext: { [weak self, weak downloader] update in
                    guard let self else { return }
                    process(
                        downloadUpdate: update,
                        toOpen: viewModel.state.attachmentToOpen,
                        downloader: downloader,
                        dataUpdate: { batchData in
                            self.viewModel.process(action: .updateDownload(update: update, batchData: batchData))
                        },
                        attachmentWillOpen: { update in
                            self.viewModel.process(action: .attachmentOpened(update.key))
                        }
                    )
                })
                .disposed(by: disposeBag)

            let identifierLookupController = controllers.userControllers?.identifierLookupController
            identifierLookupController?.observable
                .observe(on: MainScheduler.asyncInstance)
                .subscribe(onNext: { [weak self, weak identifierLookupController] update in
                    guard let self, let identifierLookupController else { return }
                    let batchData = ItemsState.IdentifierLookupBatchData(batchData: identifierLookupController.batchData)
                    viewModel.process(action: .updateIdentifierLookup(update: update, batchData: batchData))
                })
                .disposed(by: disposeBag)

            let remoteDownloader = controllers.userControllers?.remoteFileDownloader
            remoteDownloader?.observable
                .observe(on: MainScheduler.asyncInstance)
                .subscribe(onNext: { [weak self, weak remoteDownloader] update in
                    guard let self, let remoteDownloader else { return }
                    let batchData = ItemsState.DownloadBatchData(batchData: remoteDownloader.batchData)
                    viewModel.process(action: .updateRemoteDownload(update: update, batchData: batchData))
                })
                .disposed(by: disposeBag)
        }

        func setupRecognizerObserver() {
            let recognizerController = controllers.userControllers?.recognizerController
            recognizerController?.updates
                .observe(on: MainScheduler.asyncInstance)
                .subscribe(onNext: { [weak viewModel] update in
                    guard let viewModel, case .createParentForItem(let libraryId, let key) = update.task.kind, viewModel.state.library.identifier == libraryId else { return }
                    viewModel.process(action: .updateMetadataRetrieval(itemKey: key, update: update.kind))
                })
                .disposed(by: disposeBag)
        }

        func setupAppStateObserver() {
            NotificationCenter.default
                .rx
                .notification(UIContentSizeCategory.didChangeNotification)
                .observe(on: MainScheduler.instance)
                .subscribe(onNext: { [weak self] _ in
                    guard let self else { return }
                    viewModel.process(action: .clearTitleCache)
                    handler?.reloadAll()
                })
                .disposed(by: disposeBag)
        }
    }

    deinit {
        DDLogInfo("ItemsViewController deinitialized")
    }

    // MARK: - UI state

    private func update(state: ItemsState) {
        if state.changes.contains(.results), let results = state.results {
            self.startObserving(results: results)
        } else if state.changes.contains(.attachmentsRemoved) {
            handler?.attachmentAccessoriesChanged()
        } else if let itemUpdate = state.updateItem {
            switch itemUpdate.kind {
            case .accessory:
                let accessory = state.itemAccessories[itemUpdate.key].flatMap({ ItemCellModel.createAccessory(from: $0, fileDownloader: controllers.userControllers?.fileDownloader) })
                handler?.updateCell(key: itemUpdate.key, withAccessory: accessory)

            case .subtitle(let subtitle):
                handler?.updateCell(key: itemUpdate.key, withSubtitle: subtitle)
            }
        }

        if state.changes.contains(.editing) {
            handler?.set(editing: state.isEditing, animated: true)
            setupRightBarButtonItems(expectedItems: rightBarButtonItemTypes(for: state))
            toolbarController?.createToolbarItems(data: toolbarData(from: state))
        }

        if state.changes.contains(.selectAll) {
            if state.selectedItems.isEmpty {
                handler?.deselectAll()
            } else {
                handler?.selectAll()
            }
        }

        if state.changes.contains(.selection) || state.changes.contains(.library) {
            setupRightBarButtonItems(expectedItems: rightBarButtonItemTypes(for: state))
            toolbarController?.reloadToolbarItems(for: toolbarData(from: state))
        }

        if state.changes.contains(.filters) || state.changes.contains(.batchData) {
            toolbarController?.reloadToolbarItems(for: toolbarData(from: state))
        }

        if let key = state.itemKeyToDuplicate {
            coordinatorDelegate?.showItemDetail(
                for: .duplication(itemKey: key, collectionKey: self.viewModel.state.collection.identifier.key),
                libraryId: self.viewModel.state.library.identifier,
                scrolledToKey: nil,
                animated: true
            )
        }

        if let error = state.error {
            process(error: error, state: state)
        }

        func process(error: ItemsError, state: ItemsState) {
            // Perform additional actions for individual errors if needed
            switch error {
            case .itemMove, .deletion, .deletionFromCollection:
                if let snapshot = state.results {
                    dataSource.apply(snapshot: snapshot.freeze())
                }

            case .dataLoading, .collectionAssignment, .noteSaving, .attachmentAdding, .duplicationLoading:
                break
            }

            // Show appropriate message
            coordinatorDelegate?.show(error: error)
        }
    }

    // MARK: - Actions

    override func search(for term: String) {
        self.viewModel.process(action: .search(term))
    }

    private func process(action: ItemAction.Kind, for selectedKeys: Set<String>, button: UIBarButtonItem?, completionAction: ((Bool) -> Void)?) {
        switch action {
        case .delete, .restore:
            break

        case .addToCollection:
            guard !selectedKeys.isEmpty else { return }
            coordinatorDelegate?.showCollectionsPicker(in: library, completed: { [weak self] collections in
                self?.viewModel.process(action: .assignItemsToCollections(items: selectedKeys, collections: collections))
                completionAction?(true)
            })

        case .createParent:
            guard let key = selectedKeys.first, case .attachment(let attachment, _) = viewModel.state.itemAccessories[key] else { return }
            coordinatorDelegate?.showItemDetail(
                for: .creation(type: ItemTypes.document, child: attachment, collectionsSource: .fromChildren),
                libraryId: library.identifier,
                scrolledToKey: nil,
                animated: true
            )

        case .retrieveMetadata:
            guard let key = selectedKeys.first,
                  case .attachment(let attachment, let parentKey) = viewModel.state.itemAccessories[key],
                  parentKey == nil,
                  let file = attachment.file as? FileData,
                  file.mimeType == "application/pdf",
                  let recognizerController = controllers.userControllers?.recognizerController
            else { return }
            recognizerController.queue(task: RecognizerController.RecognizerTask(file: file, kind: .createParentForItem(libraryId: library.identifier, key: key)))

        case .duplicate:
            guard let key = selectedKeys.first else { return }
            viewModel.process(action: .loadItemToDuplicate(key))

        case .removeFromCollection:
            guard !selectedKeys.isEmpty else { return }
            coordinatorDelegate?.showRemoveFromCollectionQuestion(
                count: viewModel.state.selectedItems.count
            ) { [weak self] in
                self?.viewModel.process(action: .deleteItemsFromCollection(selectedKeys))
                completionAction?(true)
            }

        case .trash:
            guard !selectedKeys.isEmpty else { return }
            viewModel.process(action: .trashItems(selectedKeys))

        case .filter:
            guard let button else { return }
            coordinatorDelegate?.showFilters(filters: viewModel.state.filters, filtersDelegate: self, button: button)

        case .sort:
            guard let button else { return }
            coordinatorDelegate?.showSortActions(
                sortType: viewModel.state.sortType,
                button: button,
                changed: { [weak self] newValue in
                    self?.viewModel.process(action: .setSortType(newValue))
                }
            )

        case .share:
            guard !selectedKeys.isEmpty else { return }
            coordinatorDelegate?.showCiteExport(for: selectedKeys, libraryId: library.identifier)

        case .copyBibliography:
            var presenter: UIViewController = self
            if let searchController = navigationItem.searchController, searchController.isActive {
                presenter = searchController
            }
            coordinatorDelegate?.copyBibliography(using: presenter, for: selectedKeys, libraryId: library.identifier, delegate: nil)

        case .copyCitation:
            coordinatorDelegate?.showCitation(using: nil, for: selectedKeys, libraryId: library.identifier, delegate: nil)

        case .download:
            viewModel.process(action: .download(selectedKeys))

        case .removeDownload:
            viewModel.process(action: .removeDownloads(selectedKeys))
        }
    }

    override func process(barButtonItemAction: BaseItemsViewController.RightBarButtonItem, sender: UIBarButtonItem) {
        switch barButtonItemAction {
        case .add:
            coordinatorDelegate?.showAddActions(viewModel: viewModel, button: sender)

        case .deselectAll, .selectAll:
            viewModel.process(action: .toggleSelectionState)

        case .done:
            viewModel.process(action: .stopEditing)

        case .emptyTrash:
            break

        case .select:
            viewModel.process(action: .startEditing)
        }
    }

    private func startObserving(results: Results<RItem>) {
        resultsToken = results.observe(keyPaths: RItem.observableKeypathsForItemList, { [weak self] changes in
            guard let self else { return }
            switch changes {
            case .initial(let results):
                dataSource.apply(snapshot: results.freeze())
                updateTagFilter(filters: viewModel.state.filters, collectionId: collection.identifier, libraryId: library.identifier)

            case .update(let results, let deletions, let insertions, let modifications):
                let correctedModifications = Database.correctedModifications(from: modifications, insertions: insertions, deletions: deletions)
                viewModel.process(action: .updateKeys(items: results, deletions: deletions, insertions: insertions, modifications: correctedModifications))
                dataSource.apply(snapshot: results.freeze(), modifications: modifications, insertions: insertions, deletions: deletions) { [weak self] in
                    guard let self else { return }
                    updateTagFilter(filters: viewModel.state.filters, collectionId: collection.identifier, libraryId: library.identifier)
                }

            case .error(let error):
                DDLogError("ItemsViewController: could not load results - \(error)")
                viewModel.process(action: .observingFailed)
            }
        })
    }

    // MARK: - Tag filter delegate

    override func tagSelectionDidChange(selected: Set<String>) {
        if selected.isEmpty {
            if let tags = viewModel.state.filters.compactMap({ $0.tags }).first {
                viewModel.process(action: .disableFilter(.tags(tags)))
            }
        } else {
            viewModel.process(action: .enableFilter(.tags(selected)))
        }
    }

    override func downloadsFilterDidChange(enabled: Bool) {
        if enabled {
            viewModel.process(action: .enableFilter(.downloadedFiles))
        } else {
            viewModel.process(action: .disableFilter(.downloadedFiles))
        }
    }

    // MARK: - Helpers

    private func toolbarData(from state: ItemsState) -> ItemsToolbarController.Data {
        return .init(
            isEditing: state.isEditing,
            selectedItems: state.selectedItems,
            filters: state.filters,
            downloadBatchData: state.downloadBatchData,
            remoteDownloadBatchData: state.remoteDownloadBatchData,
            identifierLookupBatchData: state.identifierLookupBatchData,
            itemCount: state.results?.count ?? 0
        )
    }

    private func rightBarButtonItemTypes(for state: ItemsState) -> [RightBarButtonItem] {
        let selectItems = rightBarButtonSelectItemTypes(for: state)
        return state.library.metadataEditable ? [.add] + selectItems : selectItems

        func rightBarButtonSelectItemTypes(for state: ItemsState) -> [RightBarButtonItem] {
            if !state.isEditing {
                return [.select]
            }
            if state.selectedItems.count == (state.results?.count ?? 0) {
                return [.deselectAll, .done]
            }
            return [.selectAll, .done]
        }
    }
}

extension ItemsViewController: ItemsTableViewHandlerDelegate {
    var collectionKey: String? {
        return collection.identifier.key
    }

    var isInViewHierarchy: Bool {
        return view.window != nil
    }

    func process(tapAction: ItemsTableViewHandler.TapAction) {
        resetActiveSearch()

        switch tapAction {
        case .metadata(let object):
            coordinatorDelegate?.showItemDetail(for: .preview(key: object.key), libraryId: viewModel.state.library.identifier, scrolledToKey: nil, animated: true)

        case .attachment(let attachment, let parentKey):
            viewModel.process(action: .openAttachment(attachment: attachment, parentKey: parentKey))

        case .doi(let doi):
            coordinatorDelegate?.show(doi: doi)

        case .url(let url):
            coordinatorDelegate?.show(url: url)

        case .selectItem(let object):
            viewModel.process(action: .selectItem(object.key))

        case .deselectItem(let object):
            viewModel.process(action: .deselectItem(object.key))

        case .note(let object):
            guard let item = object as? RItem, let note = Note(item: item) else { return }
            let tags = Array(item.tags.map({ Tag(tag: $0) }))
            coordinatorDelegate?.showNote(library: viewModel.state.library, kind: .edit(key: note.key), text: note.text, tags: tags, parentTitleData: nil, title: note.title, saveCallback: nil)
        }

        func resetActiveSearch() {
            guard let searchBar = navigationItem.searchController?.searchBar else { return }
            searchBar.resignFirstResponder()
        }
    }

    func process(action: ItemAction.Kind, at index: Int, completionAction: ((Bool) -> Void)?) {
        guard let object = dataSource.object(at: index) else { return }
        process(action: action, for: [object.key], button: nil, completionAction: completionAction)
    }

    func process(dragAndDropAction action: ItemsTableViewHandler.DragAndDropAction) {
        switch action {
        case .moveItems(let keys, let toKey):
            viewModel.process(action: .moveItems(keys: keys, toItemKey: toKey))

        case .tagItem(let key, let libraryId, let tags):
            viewModel.process(action: .tagItem(itemKey: key, libraryId: libraryId, tagNames: tags))
        }
    }
}

extension ItemsViewController: ItemsToolbarControllerDelegate {
    func process(action: ItemAction.Kind, button: UIBarButtonItem) {
        process(action: action, for: viewModel.state.selectedItems, button: button, completionAction: nil)
    }
    
    func showLookup() {
        coordinatorDelegate?.showLookup()
    }
}

extension ItemsViewController: DetailCoordinatorAttachmentProvider {
    func attachment(for key: String, parentKey: String?, libraryId: LibraryIdentifier) -> (Attachment, UIView, CGRect?)? {
        guard
            let accessory = self.viewModel.state.itemAccessories[parentKey ?? key],
            let attachment = accessory.attachment,
            let (sourceView, sourceRect) = handler?.sourceDataForCell(for: (parentKey ?? key))
        else { return nil }
        return (attachment, sourceView, sourceRect)
    }
}
