//
//  TrashViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 18.07.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

final class TrashViewController: BaseItemsViewController {
    private let viewModel: ViewModel<TrashActionHandler>

    private var dataSource: TrashTableViewDataSource!
    override var library: Library {
        return viewModel.state.library
    }
    override var collection: Collection {
        return .init(custom: .trash)
    }
    override var toolbarData: ItemsToolbarController.Data {
        return toolbarData(from: viewModel.state)
    }

    init(viewModel: ViewModel<TrashActionHandler>, controllers: Controllers, coordinatorDelegate: (DetailItemsCoordinatorDelegate & DetailNoteEditorCoordinatorDelegate)) {
        self.viewModel = viewModel
        super.init(controllers: controllers, coordinatorDelegate: coordinatorDelegate)
        viewModel.process(action: .loadData)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        dataSource = TrashTableViewDataSource(viewModel: viewModel, fileDownloader: controllers.userControllers?.fileDownloader)
        handler = ItemsTableViewHandler(tableView: tableView, delegate: self, dataSource: dataSource, dragDropController: controllers.dragDropController)
        toolbarController = ItemsToolbarController(viewController: self, data: toolbarData, collection: collection, library: library, delegate: self)
        setupRightBarButtonItems(expectedItems: rightBarButtonItemTypes(for: viewModel.state))
        setupDownloadObserver()
        dataSource.apply(snapshot: viewModel.state.objects)

        viewModel
            .stateObservable
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] state in
                self?.update(state: state)
            })
            .disposed(by: self.disposeBag)

        func setupDownloadObserver() {
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

            NotificationCenter.default
                .rx
                .notification(.attachmentFileDeleted)
                .observe(on: MainScheduler.instance)
                .subscribe(onNext: { [weak self] notification in
                    if let notification = notification.object as? AttachmentFileDeletedNotification {
                        self?.viewModel.process(action: .updateAttachments(notification))
                    }
                })
                .disposed(by: self.disposeBag)
        }
    }

    // MARK: - Actions

    private func update(state: TrashState) {
        if state.changes.contains(.objects) {
            dataSource.apply(snapshot: state.objects)
            updateTagFilter(filters: state.filters, collectionId: .custom(.trash), libraryId: state.library.identifier)
        } else if let key = state.updateItemKey, let object = state.objects[key] {
            let accessory = ItemCellModel.createAccessory(from: object.itemAccessory, fileDownloader: controllers.userControllers?.fileDownloader)
            handler?.updateCell(key: key.key, withAccessory: accessory)
        } else if state.changes.contains(.attachmentsRemoved) {
            handler?.attachmentAccessoriesChanged()
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

        if state.changes.contains(.selection) {// || state.changes.contains(.library) {
            setupRightBarButtonItems(expectedItems: rightBarButtonItemTypes(for: state))
            toolbarController?.reloadToolbarItems(for: toolbarData(from: state))
        }

        if state.changes.contains(.filters) {// || state.changes.contains(.batchData) {
            toolbarController?.reloadToolbarItems(for: toolbarData(from: state))
        }

        if let error = state.error {
            process(error: error, state: state)
        }

        func process(error: ItemsError, state: TrashState) {
            // Perform additional actions for individual errors if needed
            switch error {
            case .itemMove, .deletion, .deletionFromCollection:
                dataSource.apply(snapshot: state.objects)

            case .dataLoading, .collectionAssignment, .noteSaving, .attachmentAdding, .duplicationLoading:
                break
            }

            // Show appropriate message
            coordinatorDelegate?.show(error: error)
        }
    }

    override func search(for term: String) {
        viewModel.process(action: .search(term))
    }

    private func process(action: ItemAction.Kind, for selectedKeys: Set<TrashKey>, button: UIBarButtonItem?, completionAction: ((Bool) -> Void)?) {
        switch action {
        case .createParent, .duplicate, .trash, .copyBibliography, .copyCitation, .share, .addToCollection, .removeFromCollection:
            // These actions are not available in trash collection
            break

        case .delete:
            guard !selectedKeys.isEmpty else { return }
            coordinatorDelegate?.showDeletionQuestion(
                count: selectedKeys.count,
                confirmAction: { [weak self] in
                    self?.viewModel.process(action: .deleteObjects(selectedKeys))
                },
                cancelAction: {
                    completionAction?(false)
                }
            )

        case .restore:
            guard !selectedKeys.isEmpty else { return }
            viewModel.process(action: .restoreItems(selectedKeys))
            completionAction?(true)

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

        case .download:
            viewModel.process(action: .download(selectedKeys))

        case .removeDownload:
            viewModel.process(action: .removeDownloads(selectedKeys))
        }
    }

    override func process(barButtonItemAction: BaseItemsViewController.RightBarButtonItem, sender: UIBarButtonItem) {
        switch barButtonItemAction {
        case .add:
            break

        case .deselectAll, .selectAll:
            viewModel.process(action: .toggleSelectionState)

        case .done:
            viewModel.process(action: .stopEditing)

        case .emptyTrash:
            viewModel.process(action: .emptyTrash)

        case .select:
            viewModel.process(action: .startEditing)
        }
    }

    // MARK: - Helpers

    private func toolbarData(from state: TrashState) -> ItemsToolbarController.Data {
        return .init(
            isEditing: state.isEditing,
            selectedItems: state.selectedItems,
            filters: state.filters,
            downloadBatchData: nil,
            remoteDownloadBatchData: nil,
            identifierLookupBatchData: .init(saved: 0, total: 0),
            itemCount: state.objects.count
        )
    }

    private func rightBarButtonItemTypes(for state: TrashState) -> [RightBarButtonItem] {
        let selectItems = rightBarButtonSelectItemTypes(for: state)
        return selectItems + [.emptyTrash]

        func rightBarButtonSelectItemTypes(for state: TrashState) -> [RightBarButtonItem] {
            if !state.isEditing {
                return [.select]
            }
            if state.selectedItems.count == state.objects.count {
                return [.deselectAll, .done]
            }
            return [.selectAll, .done]
        }
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
}

extension TrashViewController: ItemsTableViewHandlerDelegate {
    var isInViewHierarchy: Bool {
        return view.window != nil
    }
    
    var collectionKey: String? {
        return nil
    }
    
    func process(action: ItemAction.Kind, at index: Int, completionAction: ((Bool) -> Void)?) {
        guard let key = dataSource.key(at: index) else { return }
        process(action: action, for: [key], button: nil, completionAction: completionAction)
    }
    
    func process(tapAction action: ItemsTableViewHandler.TapAction) {
        resetActiveSearch()

        switch action {
        case .metadata(let object):
            coordinatorDelegate?.showItemDetail(for: .preview(key: object.key), libraryId: viewModel.state.library.identifier, scrolledToKey: nil, animated: true)

        case .attachment(let attachment, let parentKey):
            viewModel.process(action: .openAttachment(attachment: attachment, parentKey: parentKey))

        case .doi(let doi):
            coordinatorDelegate?.show(doi: doi)

        case .url(let url):
            coordinatorDelegate?.show(url: url)

        case .selectItem(let object):
            guard let trashObject = object as? TrashObject else { return }
            viewModel.process(action: .selectItem(trashObject.trashKey))

        case .deselectItem(let object):
            guard let trashObject = object as? TrashObject else { return }
            viewModel.process(action: .deselectItem(trashObject.trashKey))

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
    
    func process(dragAndDropAction action: ItemsTableViewHandler.DragAndDropAction) {
        switch action {
        case .moveItems:
            // Action not supported in trash
            break

        case .tagItem(let key, let libraryId, let tags):
            viewModel.process(action: .tagItem(itemKey: key, libraryId: libraryId, tagNames: tags))
        }
    }
}

extension TrashViewController: ItemsToolbarControllerDelegate {
    func process(action: ItemAction.Kind, button: UIBarButtonItem) {
        process(action: action, for: viewModel.state.selectedItems, button: button, completionAction: nil)
    }

    func showLookup() {
        coordinatorDelegate?.showLookup()
    }
}
