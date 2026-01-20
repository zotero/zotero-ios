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

    init(
        viewModel: ViewModel<TrashActionHandler>,
        controllers: Controllers,
        coordinatorDelegate: (DetailItemsCoordinatorDelegate & DetailNoteEditorCoordinatorDelegate),
        presenter: OpenItemsPresenter
    ) {
        self.viewModel = viewModel
        super.init(controllers: controllers, coordinatorDelegate: coordinatorDelegate, presenter: presenter)
        viewModel.process(action: .loadData)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        dataSource = TrashTableViewDataSource(viewModel: viewModel, schemaController: controllers.schemaController, fileDownloader: controllers.userControllers?.fileDownloader)
        handler = ItemsTableViewHandler(
            tableView: tableView,
            delegate: self,
            dataSource: dataSource,
            dragDropController: controllers.userControllers?.dragDropController
        )
        toolbarController = ItemsToolbarController(viewController: self, data: toolbarData, collection: collection, library: library, delegate: self)
        setupRightBarButtonItems(expectedItems: rightBarButtonItemTypes(for: viewModel.state))
        setupDownloadObserver()
        setupOpenItemsObserving()
        dataSource.apply(snapshot: viewModel.state.snapshot)
        updateTagFilter(filters: viewModel.state.filters, collectionId: .custom(.trash), libraryId: viewModel.state.library.identifier)

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
                .disposed(by: disposeBag)
        }

        func setupOpenItemsObserving() {
            guard let controller = controllers.userControllers?.openItemsController, let sessionIdentifier else { return }
            controller.observable(for: sessionIdentifier)
                .observe(on: MainScheduler.instance)
                .subscribe(onNext: { [weak self] items in
                    self?.viewModel.process(action: .updateOpenItems(items: items))
                })
                .disposed(by: disposeBag)
        }
    }

    // MARK: - Actions

    private func update(state: TrashState) {
        if state.changes.contains(.objects) {
            dataSource.apply(snapshot: state.snapshot)
            updateTagFilter(filters: state.filters, collectionId: .custom(.trash), libraryId: state.library.identifier)
        } else if let key = state.updateItemKey, let accessory = state.itemDataCache[key]?.accessory {
            dataSource.updateCellAccessory(key: key, itemAccessory: accessory)
        } else if state.changes.contains(.attachmentsRemoved) {
            dataSource.updateAttachmentAccessories()
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

        if state.changes.contains(.openItems) {
            setupRightBarButtonItems(expectedItems: rightBarButtonItemTypes(for: state))
        }

        if let error = state.error {
            process(error: error, state: state)
        }

        func process(error: ItemsError, state: TrashState) {
            // Perform additional actions for individual errors if needed
            switch error {
            case .itemMove, .deletion, .deletionFromCollection:
                dataSource.apply(snapshot: state.snapshot)

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
        case .createParent, .retrieveMetadata, .duplicate, .trash, .copyBibliography, .copyCitation, .share, .addToCollection, .removeFromCollection:
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

        case .debugReader:
            break
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

        case .restoreOpenItems:
            super.process(barButtonItemAction: barButtonItemAction, sender: sender)
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
            itemCount: state.snapshot.count
        )
    }

    override func setupRightBarButtonItems(expectedItems: [RightBarButtonItem]) {
        defer {
            updateRestoreOpenItemsButton(withCount: viewModel.state.openItemsCount)
        }
        super.setupRightBarButtonItems(expectedItems: expectedItems)

        func updateRestoreOpenItemsButton(withCount count: Int) {
            guard let item = navigationItem.rightBarButtonItems?.first(where: { button in RightBarButtonItem(rawValue: button.tag) == .restoreOpenItems }) else { return }
            item.image = .openItemsImage(count: count)
        }
    }

    private func rightBarButtonItemTypes(for state: TrashState) -> [RightBarButtonItem] {
        var items = rightBarButtonSelectItemTypes(for: state) + [.emptyTrash]
        if FeatureGates.enabled.contains(.multipleOpenItems), state.openItemsCount > 0 {
            items = [.restoreOpenItems] + items
        }
        return items

        func rightBarButtonSelectItemTypes(for state: TrashState) -> [RightBarButtonItem] {
            if !state.isEditing {
                return [.select]
            }
            if state.selectedItems.count == state.snapshot.count {
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

    override func downloadsFilterDidChange(enabled: Bool) {
        if enabled {
            viewModel.process(action: .enableFilter(.downloadedFiles))
        } else {
            viewModel.process(action: .disableFilter(.downloadedFiles))
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

    func process(action: ItemAction.Kind, at indexPath: IndexPath, completionAction: ((Bool) -> Void)?) {
        if action == .debugReader {
            guard let tapAction = dataSource.tapAction(for: indexPath) else { return }
            processDebugReaderAction(tapAction: tapAction) { [weak self] in
                self?.process(tapAction: tapAction)
            }
            return
        }
        guard let key = dataSource.key(at: indexPath.row) else { return }
        process(action: action, for: [key], button: nil, completionAction: completionAction)
    }

    func process(tapAction action: ItemsTableViewHandler.TapAction) {
        resetActiveSearch()

        switch action {
        case .metadata(let object):
            guard object is RItem else { return }
            coordinatorDelegate?.showItemDetail(for: .preview(key: object.key), libraryId: viewModel.state.library.identifier, scrolledToKey: nil, animated: true)

        case .attachment(let attachment, let parentKey):
            viewModel.process(action: .openAttachment(attachment: attachment, parentKey: parentKey))

        case .doi(let doi):
            coordinatorDelegate?.show(doi: doi)

        case .url(let url):
            coordinatorDelegate?.show(url: url)

        case .selectItem(let object):
            viewModel.process(action: .selectItem(TrashKey(type: .item, key: object.key)))

        case .deselectItem(let object):
            viewModel.process(action: .deselectItem(TrashKey(type: .item, key: object.key)))

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

extension TrashViewController: DetailCoordinatorAttachmentProvider {
    func attachment(for key: String, parentKey: String?, libraryId: LibraryIdentifier) -> (Attachment, UIPopoverPresentationControllerSourceItem)? {
        guard let accessory = viewModel.state.itemDataCache[TrashKey(type: .item, key: parentKey ?? key)]?.accessory, let attachment = accessory.attachment, let handler else { return nil }
        let sourceItem = handler.sourceItemForCell(for: (parentKey ?? key))
        return (attachment, sourceItem)
    }
}
