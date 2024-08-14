//
//  ItemsViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 17/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift
import RealmSwift
import RxSwift
import WebKit

final class ItemsViewController: UIViewController {
    private enum RightBarButtonItem: Int {
        case select
        case done
        case selectAll
        case deselectAll
        case add
        case emptyTrash
    }

    @IBOutlet private weak var tableView: UITableView!

    private static let itemBatchingLimit = 150

    private let viewModel: ViewModel<ItemsActionHandler>
    private unowned let controllers: Controllers
    private let disposeBag: DisposeBag

    private var tableViewHandler: ItemsTableViewHandler!
    private var toolbarController: ItemsToolbarController!
    private var resultsToken: NotificationToken?
    private var libraryToken: NotificationToken?
    private var refreshController: SyncRefreshController!
    weak var tagFilterDelegate: ItemsTagFilterDelegate?

    private weak var coordinatorDelegate: (DetailItemsCoordinatorDelegate & DetailNoteEditorCoordinatorDelegate)?

    init(viewModel: ViewModel<ItemsActionHandler>, controllers: Controllers, coordinatorDelegate: (DetailItemsCoordinatorDelegate & DetailNoteEditorCoordinatorDelegate)) {
        self.viewModel = viewModel
        self.controllers = controllers
        self.coordinatorDelegate = coordinatorDelegate
        self.disposeBag = DisposeBag()

        super.init(nibName: "ItemsViewController", bundle: nil)

        viewModel.process(action: .loadInitialState)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.tableViewHandler = ItemsTableViewHandler(
            tableView: self.tableView,
            viewModel: self.viewModel,
            delegate: self,
            dragDropController: self.controllers.dragDropController,
            fileDownloader: self.controllers.userControllers?.fileDownloader,
            schemaController: self.controllers.schemaController
        )
        self.toolbarController = ItemsToolbarController(viewController: self, initialState: self.viewModel.state, delegate: self)
        self.navigationController?.toolbar.barTintColor = UIColor(dynamicProvider: { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? .black : .white
        })
        self.setupRightBarButtonItems(for: self.viewModel.state)
        self.setupTitle()
        self.setupSearchBar()
        if let scheduler = controllers.userControllers?.syncScheduler {
            refreshController = SyncRefreshController(libraryId: viewModel.state.library.identifier, view: tableView, syncScheduler: scheduler)
        }
        self.setupFileObservers()
        self.startObservingSyncProgress()
        self.setupAppStateObserver()

        if let term = self.viewModel.state.searchTerm, !term.isEmpty {
            navigationItem.searchController?.searchBar.text = term
        }
        if let results = self.viewModel.state.results {
            self.startObserving(results: results)
        }

        self.tableViewHandler
            .tapObserver
            .observe(on: MainScheduler.instance)
            .subscribe(with: self, onNext: { `self`, action in
                self.resetActiveSearch()
                self.handle(action: action)
            })
            .disposed(by: self.disposeBag)

        self.viewModel
            .stateObservable
            .observe(on: MainScheduler.instance)
            .subscribe(with: self, onNext: { `self`, state in
                self.update(state: state)
            })
            .disposed(by: self.disposeBag)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.toolbarController.willAppear()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        
        // willTransition(to:with:) seems to not be not called for all transitions, so instead traitCollectionDidChange(_:) is used w/ a short animation block.
        guard UIDevice.current.userInterfaceIdiom == .pad, traitCollection.horizontalSizeClass != previousTraitCollection?.horizontalSizeClass else { return }
        self.setupTitle()
        UIView.animate(withDuration: 0.1) {
            self.toolbarController.reloadToolbarItems(for: self.viewModel.state)
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let key = presses.first?.key, key.characters == "f", key.modifierFlags.contains(.command) else {
            super.pressesBegan(presses, with: event)
            return
        }
        navigationItem.searchController?.searchBar.becomeFirstResponder()
    }

    deinit {
        DDLogInfo("ItemsViewController deinitialized")
    }

    // MARK: - UI state

    private func update(state: ItemsState) {
        if state.changes.contains(.results), let results = state.results {
            self.startObserving(results: results)
        } else if state.changes.contains(.attachmentsRemoved) {
            self.tableViewHandler.reloadAllAttachments()
        } else if let key = state.updateItemKey {
            self.tableViewHandler.updateCell(with: state.itemAccessories[key], key: key)
        }

        if state.changes.contains(.editing) {
            self.tableViewHandler.set(editing: state.isEditing, animated: true)
            self.setupRightBarButtonItems(for: state)
            self.toolbarController.createToolbarItems(for: state)
        }

        if state.changes.contains(.selectAll) {
            if state.selectedItems.isEmpty {
                self.tableViewHandler.deselectAll()
            } else {
                self.tableViewHandler.selectAll()
            }
        }

        if state.changes.contains(.selection) || state.changes.contains(.library) {
            self.setupRightBarButtonItems(for: state)
            self.toolbarController.reloadToolbarItems(for: state)
        }

        if state.changes.contains(.filters) || state.changes.contains(.batchData) {
            self.toolbarController.reloadToolbarItems(for: state)
        }

        if let key = state.itemKeyToDuplicate {
            self.coordinatorDelegate?.showItemDetail(
                for: .duplication(itemKey: key, collectionKey: self.viewModel.state.collection.identifier.key),
                libraryId: self.viewModel.state.library.identifier,
                scrolledToKey: nil,
                animated: true
            )
        }

        if let error = state.error {
            self.process(error: error, state: state)
        }
    }

    // MARK: - Actions

    private func handle(action: ItemsTableViewHandler.TapAction) {
        switch action {
        case .metadata(let item):
            self.coordinatorDelegate?.showItemDetail(for: .preview(key: item.key), libraryId: self.viewModel.state.library.identifier, scrolledToKey: nil, animated: true)

        case .attachment(let attachment, let parentKey):
            self.viewModel.process(action: .openAttachment(attachment: attachment, parentKey: parentKey))

        case .doi(let doi):
            self.coordinatorDelegate?.show(doi: doi)

        case .url(let url):
            self.coordinatorDelegate?.show(url: url)

        case .selectItem(let key):
            self.viewModel.process(action: .selectItem(key))

        case .note(let item):
            guard let note = Note(item: item) else { return }
            let tags = Array(item.tags.map({ Tag(tag: $0) }))
            let library = self.viewModel.state.library
            coordinatorDelegate?.showNote(library: library, kind: .edit(key: note.key), text: note.text, tags: tags, parentTitleData: nil, title: note.title) { [weak self] _, result in
                self?.viewModel.process(action: .processNoteSaveResult(result))
            }
        }
    }

    private func updateTagFilter(with state: ItemsState) {
        self.tagFilterDelegate?.itemsDidChange(filters: state.filters, collectionId: state.collection.identifier, libraryId: state.library.identifier)
    }

    private func process(error: ItemsError, state: ItemsState) {
        // Perform additional actions for individual errors if needed
        switch error {
        case .itemMove, .deletion, .deletionFromCollection:
            if let snapshot = state.results {
                self.tableViewHandler.reloadAll(snapshot: snapshot.freeze())
            }
        case .dataLoading, .collectionAssignment, .noteSaving, .attachmentAdding, .duplicationLoading: break
        }

        // Show appropriate message
        self.coordinatorDelegate?.show(error: error)
    }

    private func process(action: ItemAction.Kind, for selectedKeys: Set<String>, button: UIBarButtonItem?, completionAction: ((Bool) -> Void)?) {
        switch action {
        case .addToCollection:
            guard !selectedKeys.isEmpty else { return }
            self.coordinatorDelegate?.showCollectionsPicker(in: self.viewModel.state.library, completed: { [weak self] collections in
                self?.viewModel.process(action: .assignItemsToCollections(items: selectedKeys, collections: collections))
                completionAction?(true)
            })

        case .createParent:
            guard let key = selectedKeys.first, case .attachment(let attachment, _) = self.viewModel.state.itemAccessories[key] else { return }
            var collectionKey: String?
            switch self.viewModel.state.collection.identifier {
            case .collection(let _key):
                collectionKey = _key
            default: break
            }

            self.coordinatorDelegate?.showItemDetail(
                for: .creation(type: ItemTypes.document, child: attachment, collectionKey: collectionKey),
                libraryId: self.viewModel.state.library.identifier,
                scrolledToKey: nil,
                animated: true
            )

        case .delete:
            guard !selectedKeys.isEmpty else { return }
            self.coordinatorDelegate?.showDeletionQuestion(count: self.viewModel.state.selectedItems.count, confirmAction: { [weak self] in
                self?.viewModel.process(action: .deleteItems(selectedKeys))
            }, cancelAction: {
                completionAction?(false)
            })

        case .duplicate:
            guard let key = selectedKeys.first else { return }
            self.viewModel.process(action: .loadItemToDuplicate(key))

        case .removeFromCollection:
            guard !selectedKeys.isEmpty else { return }
            self.coordinatorDelegate?.showRemoveFromCollectionQuestion(count: self.viewModel.state.selectedItems.count) { [weak self] in
                self?.viewModel.process(action: .deleteItemsFromCollection(selectedKeys))
                completionAction?(true)
            }

        case .restore:
            guard !selectedKeys.isEmpty else { return }
            self.viewModel.process(action: .restoreItems(selectedKeys))
            completionAction?(true)

        case .trash:
            guard !selectedKeys.isEmpty else { return }
            self.viewModel.process(action: .trashItems(selectedKeys))

        case .filter:
            guard let button = button else { return }
            self.coordinatorDelegate?.showFilters(viewModel: self.viewModel, itemsController: self, button: button)

        case .sort:
            guard let button = button else { return }
            self.coordinatorDelegate?.showSortActions(viewModel: self.viewModel, button: button)

        case .share:
            guard !selectedKeys.isEmpty else { return }
            self.coordinatorDelegate?.showCiteExport(for: selectedKeys, libraryId: self.viewModel.state.library.identifier)

        case .copyBibliography:
            var presenter: UIViewController = self
            if let searchController = navigationItem.searchController, searchController.isActive {
                presenter = searchController
            }
            coordinatorDelegate?.copyBibliography(using: presenter, for: selectedKeys, libraryId: viewModel.state.library.identifier, delegate: nil)

        case .copyCitation:
            coordinatorDelegate?.showCitation(using: nil, for: selectedKeys, libraryId: viewModel.state.library.identifier, delegate: nil)

        case .download:
            self.viewModel.process(action: .download(selectedKeys))

        case .removeDownload:
            self.viewModel.process(action: .removeDownloads(selectedKeys))
        }
    }

    private func resetActiveSearch() {
        guard let searchBar = navigationItem.searchController?.searchBar else { return }
        searchBar.resignFirstResponder()
    }

    private func startObserving(results: Results<RItem>) {
        self.resultsToken = results.observe(keyPaths: RItem.observableKeypathsForItemList, { [weak self] changes in
            guard let self else { return }

            switch changes {
            case .initial(let results):
                self.tableViewHandler.reloadAll(snapshot: results.freeze())
                self.updateTagFilter(with: self.viewModel.state)

            case .update(let results, let deletions, let insertions, let modifications):
                let correctedModifications = Database.correctedModifications(from: modifications, insertions: insertions, deletions: deletions)
                self.viewModel.process(action: .updateKeys(items: results, deletions: deletions, insertions: insertions, modifications: correctedModifications))
                self.tableViewHandler.reload(snapshot: results.freeze(), modifications: modifications, insertions: insertions, deletions: deletions) {
                    self.updateTagFilter(with: self.viewModel.state)
                }
                self.updateEmptyTrashButton(toEnabled: viewModel.state.library.metadataEditable && !results.isEmpty)

            case .error(let error):
                DDLogError("ItemsViewController: could not load results - \(error)")
                self.viewModel.process(action: .observingFailed)
            }
        })
    }

    /// Starts observing progress of sync. The sync progress needs to be observed to optimize `UITableView` reloads for big syncs of items in current library.
    private func startObservingSyncProgress() {
        guard let syncController = self.controllers.userControllers?.syncScheduler.syncController else { return }

        syncController.progressObservable
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] progress in
                guard let self else { return }
                switch progress {
                case .object(let object, let progress, _, let libraryId):
                    if self.viewModel.state.library.identifier == libraryId && object == .item {
                        if let progress = progress, progress.total >= ItemsViewController.itemBatchingLimit {
                            // Disable batched reloads when there are a lot of upcoming updates. Batched updates kill tableView performance when many are performed in short period of time.
                            self.tableViewHandler.disableReloadAnimations()
                        }
                    } else {
                        // Re-enable batched reloads when items are synced.
                        self.tableViewHandler.enableReloadAnimations()
                    }

                default:
                    // Re-enable batched reloads when items are synced.
                    self.tableViewHandler.enableReloadAnimations()
                }
            })
            .disposed(by: self.disposeBag)
    }

    private func emptyTrash() {
        let count = self.viewModel.state.results?.count ?? 0
        self.coordinatorDelegate?.showDeletionQuestion(count: count, confirmAction: { [weak self] in
            self?.viewModel.process(action: .emptyTrash)
        }, cancelAction: {})
    }

    // MARK: - Setups

    private func setupAppStateObserver() {
        NotificationCenter.default
            .rx
            .notification(UIContentSizeCategory.didChangeNotification)
            .observe(on: MainScheduler.instance)
            .subscribe(with: self, onNext: { `self`, _ in
                self.viewModel.process(action: .clearTitleCache)
                self.tableViewHandler.reloadAll()
            })
            .disposed(by: self.disposeBag)
    }

    private func setupFileObservers() {
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

        let downloader = controllers.userControllers?.fileDownloader
        downloader?.observable
            .observe(on: MainScheduler.asyncInstance)
            .subscribe(with: self, onNext: { [weak downloader] `self`, update in
                if let downloader {
                    let batchData = ItemsState.DownloadBatchData(batchData: downloader.batchData)
                    self.viewModel.process(action: .updateDownload(update: update, batchData: batchData))
                }
                
                if case .progress = update.kind { return }
                
                guard self.viewModel.state.attachmentToOpen == update.key else { return }
                
                self.viewModel.process(action: .attachmentOpened(update.key))
                
                switch update.kind {
                case .ready:
                    self.coordinatorDelegate?.showAttachment(key: update.key, parentKey: update.parentKey, libraryId: update.libraryId)
                    
                case .failed(let error):
                    self.coordinatorDelegate?.showAttachmentError(error)
                    
                default: break
                }
            })
            .disposed(by: self.disposeBag)

        let identifierLookupController = self.controllers.userControllers?.identifierLookupController
        identifierLookupController?.observable
            .observe(on: MainScheduler.asyncInstance)
            .subscribe(with: self, onNext: { [weak identifierLookupController] `self`, update in
                guard let identifierLookupController else { return }
                let batchData = ItemsState.IdentifierLookupBatchData(batchData: identifierLookupController.batchData)
                self.viewModel.process(action: .updateIdentifierLookup(update: update, batchData: batchData))
            })
            .disposed(by: self.disposeBag)
        
        let remoteDownloader = self.controllers.userControllers?.remoteFileDownloader
        remoteDownloader?.observable
            .observe(on: MainScheduler.asyncInstance)
            .subscribe(with: self, onNext: { [weak remoteDownloader] `self`, update in
                guard let remoteDownloader else { return }
                let batchData = ItemsState.DownloadBatchData(batchData: remoteDownloader.batchData)
                self.viewModel.process(action: .updateRemoteDownload(update: update, batchData: batchData))
            })
            .disposed(by: self.disposeBag)
    }

    private func setupTitle() {
        self.title = self.traitCollection.horizontalSizeClass == .compact ? self.viewModel.state.collection.name : nil
    }

    private func updateEmptyTrashButton(toEnabled enabled: Bool) {
        guard self.viewModel.state.collection.identifier.isTrash,
              let item = self.navigationItem.rightBarButtonItems?.first(where: { button in RightBarButtonItem(rawValue: button.tag) == .emptyTrash })
        else { return }
        item.isEnabled = enabled
    }

    private func setupRightBarButtonItems(for state: ItemsState) {
        let currentItems = (self.navigationItem.rightBarButtonItems ?? []).compactMap({ RightBarButtonItem(rawValue: $0.tag) })
        let expectedItems = rightBarButtonItemTypes(for: state)
        guard currentItems != expectedItems else { return }
        self.navigationItem.rightBarButtonItems = expectedItems.map({ createRightBarButtonItem($0) }).reversed()
        self.updateEmptyTrashButton(toEnabled: state.library.metadataEditable && state.results?.isEmpty == false)

        func rightBarButtonItemTypes(for state: ItemsState) -> [RightBarButtonItem] {
            var items: [RightBarButtonItem]
            let selectItems = rightBarButtonSelectItemTypes(for: state)
            if state.collection.identifier.isTrash {
                items = selectItems + [.emptyTrash]
            } else if state.library.metadataEditable {
                items = [.add] + selectItems
            } else {
                items = selectItems
            }
            return items
            
            func rightBarButtonSelectItemTypes(for state: ItemsState) -> [RightBarButtonItem] {
                if !state.isEditing {
                    return [.select]
                }
                
                let allSelected = state.selectedItems.count == (state.results?.count ?? 0)
                if allSelected {
                    return [.deselectAll, .done]
                }
                
                return [.selectAll, .done]
            }
        }
        
        func createRightBarButtonItem(_ type: RightBarButtonItem) -> UIBarButtonItem {
            var image: UIImage?
            var title: String?
            let primaryAction: UIAction?
            var menu: UIMenu?
            let accessibilityLabel: String
            
            switch type {
            case .deselectAll:
                title = L10n.Items.deselectAll
                accessibilityLabel = L10n.Accessibility.Items.deselectAllItems
                primaryAction = UIAction { [weak self] _ in
                    self?.viewModel.process(action: .toggleSelectionState)
                }
                
            case .selectAll:
                title = L10n.Items.selectAll
                accessibilityLabel = L10n.Accessibility.Items.selectAllItems
                primaryAction = UIAction { [weak self] _ in
                    self?.viewModel.process(action: .toggleSelectionState)
                }
                
            case .done:
                title = L10n.done
                accessibilityLabel = L10n.done
                primaryAction = UIAction { [weak self] _ in
                    self?.viewModel.process(action: .stopEditing)
                }
                
            case .select:
                title = L10n.select
                accessibilityLabel = L10n.Accessibility.Items.selectItems
                primaryAction = UIAction { [weak self] _ in
                    self?.viewModel.process(action: .startEditing)
                }
                
            case .add:
                image = UIImage(systemName: "plus")
                accessibilityLabel = L10n.Items.new
                title = L10n.Items.new
                primaryAction = UIAction { [weak self] action in
                    guard let self, let sender = action.sender as? UIBarButtonItem else { return }
                    coordinatorDelegate?.showAddActions(viewModel: viewModel, button: sender)
                }
                
            case .emptyTrash:
                title = L10n.Collections.emptyTrash
                accessibilityLabel = L10n.Collections.emptyTrash
                primaryAction = UIAction { [weak self] _ in
                    self?.emptyTrash()
                }
            }
            
            let item = UIBarButtonItem(title: title, image: image, primaryAction: primaryAction, menu: menu)
            item.tag = type.rawValue
            item.accessibilityLabel = accessibilityLabel
            return item
        }
    }

    private func setupSearchBar() {
        let controller = UISearchController(searchResultsController: nil)
        controller.searchBar.placeholder = L10n.Items.searchTitle
        controller.searchBar.rx
            .text.observe(on: MainScheduler.instance)
            .skip(1)
            .debounce(.milliseconds(150), scheduler: MainScheduler.instance)
            .subscribe(onNext: { [weak self] text in
                self?.viewModel.process(action: .search(text ?? ""))
            })
            .disposed(by: disposeBag)
        controller.obscuresBackgroundDuringPresentation = false
        controller.delegate = self
        navigationItem.hidesSearchBarWhenScrolling = false
        navigationItem.searchController = controller
    }
}

extension ItemsViewController: ItemsTableViewHandlerDelegate {
    func process(action: ItemAction.Kind, for item: RItem, completionAction: ((Bool) -> Void)?) {
        self.process(action: action, for: [item.key], button: nil, completionAction: completionAction)
    }

    var isInViewHierarchy: Bool {
        return self.view.window != nil
    }
}

extension ItemsViewController: DetailCoordinatorAttachmentProvider {
    func attachment(for key: String, parentKey: String?, libraryId: LibraryIdentifier) -> (Attachment, UIView, CGRect?)? {
        guard let accessory = self.viewModel.state.itemAccessories[parentKey ?? key], let attachment = accessory.attachment else { return nil }
        let (sourceView, sourceRect) = self.tableViewHandler.sourceDataForCell(for: (parentKey ?? key))
        return (attachment, sourceView, sourceRect)
    }
}

extension ItemsViewController: ItemsToolbarControllerDelegate {
    func process(action: ItemAction.Kind, button: UIBarButtonItem) {
        self.process(action: action, for: self.viewModel.state.selectedItems, button: button, completionAction: nil)
    }
    
    func showLookup() {
        coordinatorDelegate?.showLookup()
    }
}

extension ItemsViewController: TagFilterDelegate {
    var currentLibrary: Library {
        return self.viewModel.state.library
    }

    func tagSelectionDidChange(selected: Set<String>) {
        if selected.isEmpty {
            if let tags = self.viewModel.state.tagsFilter {
                self.viewModel.process(action: .disableFilter(.tags(tags)))
            }
        } else {
            self.viewModel.process(action: .enableFilter(.tags(selected)))
        }
    }

    func tagOptionsDidChange() {
        self.updateTagFilter(with: self.viewModel.state)
    }
}

extension ItemsViewController: UISearchControllerDelegate {
    func didDismissSearchController(_ searchController: UISearchController) {
        viewModel.process(action: .search(""))
    }
}
