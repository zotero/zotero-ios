//
//  BaseItemsViewController.swift
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

class BaseItemsViewController: UIViewController {
    enum RightBarButtonItem: Int {
        case select
        case done
        case selectAll
        case deselectAll
        case add
        case emptyTrash
    }

    private static let itemBatchingLimit = 150
    unowned let controllers: Controllers
    let disposeBag: DisposeBag

    weak var tableView: UITableView!
    var toolbarController: ItemsToolbarController?
    var refreshController: SyncRefreshController?
    var handler: ItemsTableViewHandler?
    weak var tagFilterDelegate: ItemsTagFilterDelegate?
    weak var coordinatorDelegate: (DetailItemsCoordinatorDelegate & DetailNoteEditorCoordinatorDelegate)?

    init(controllers: Controllers, coordinatorDelegate: (DetailItemsCoordinatorDelegate & DetailNoteEditorCoordinatorDelegate)) {
        self.controllers = controllers
        self.coordinatorDelegate = coordinatorDelegate
        self.disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        createTableView()
        if #unavailable(iOS 26.0.0) {
            navigationController?.toolbar.barTintColor = UIColor(dynamicProvider: { traitCollection in
                return traitCollection.userInterfaceStyle == .dark ? .black : .white
            })
        }
        setupTitle()
        setupSearchBar()
        if let scheduler = controllers.userControllers?.syncScheduler {
            refreshController = SyncRefreshController(libraryId: library.identifier, view: tableView, syncScheduler: scheduler)
        }
        startObservingSyncProgress()

        func createTableView() {
            let tableView = UITableView()
            tableView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(tableView)

            if #available(iOS 26.0.0, *) {
                NSLayoutConstraint.activate([
                    tableView.topAnchor.constraint(equalTo: view.topAnchor),
                    tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
                    tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                    tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
                ])
            } else {
                NSLayoutConstraint.activate([
                    tableView.topAnchor.constraint(equalTo: view.topAnchor),
                    tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                    tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                    tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
                ])
            }

            self.tableView = tableView
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if #available(iOS 18, *) {
            if #unavailable(iOS 26.0) {
                // In some cases in iOS 18, where the horizontal size class changes, e.g. when switching to a scene with a PDF reader and dismissing it,
                // this error is logged multiple times, and leaves the search bar in stack placement, but overlapping the table view:
                // "UINavigationBar has changed horizontal size class without updating search bar to new placement. Fixing, but delegate searchBarPlacement callbacks have been skipped."
                // Setting "navigationItem.preferredSearchBarPlacement = .inline" explicitly, would even freeze the app and crash it.
                // Instead, hiding and showing the navigation bar momentarily when the view will appear, fixes the issue.
                navigationController?.setNavigationBarHidden(true, animated: false)
                navigationController?.setNavigationBarHidden(false, animated: false)
            }
            // In iOS 26 this fix doesn't seem necessary and also causes a crash if design compatibility is off.
            // The crsh can be reproduced as following:
            // - Make a search in items.
            // - Go to an item's details from the search results.
            // - Go back, where it crases with error
                //   "Terminating app due to uncaught exception 'NSInternalInconsistencyException', reason: 'The view should already be in the window before adding a _UIPassthroughScrollInteraction'".
        }
        toolbarController?.willAppear()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        // willTransition(to:with:) seems to not be not called for all transitions, so instead traitCollectionDidChange(_:) is used w/ a short animation block.
        guard UIDevice.current.userInterfaceIdiom == .pad, traitCollection.horizontalSizeClass != previousTraitCollection?.horizontalSizeClass else { return }
        setupTitle()
        UIView.animate(withDuration: 0.1) {
            self.toolbarController?.reloadToolbarItems(for: self.toolbarData)
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let key = presses.first?.key, key.characters == "f", key.modifierFlags.contains(.command) else {
            super.pressesBegan(presses, with: event)
            return
        }
        navigationItem.searchController?.searchBar.becomeFirstResponder()
    }

    // MARK: - Actions

    func updateTagFilter(filters: [ItemsFilter], collectionId: CollectionIdentifier, libraryId: LibraryIdentifier) {
        tagFilterDelegate?.itemsDidChange(filters: filters, collectionId: collection.identifier, libraryId: library.identifier)
    }

    /// Starts observing progress of sync. The sync progress needs to be observed to optimize `UITableView` reloads for big syncs of items in current library.
    private func startObservingSyncProgress() {
        guard let syncController = controllers.userControllers?.syncScheduler.syncController else { return }

        syncController.progressObservable
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] progress in
                guard let self else { return }
                switch progress {
                case .object(let object, let progress, _, let libraryId):
                    if library.identifier == libraryId && object == .item {
                        if let progress = progress, progress.total >= BaseItemsViewController.itemBatchingLimit {
                            // Disable batched reloads when there are a lot of upcoming updates. Batched updates kill tableView performance when many are performed in short period of time.
                            handler?.disableReloadAnimations()
                        }
                    } else {
                        // Re-enable batched reloads when items are synced.
                        handler?.enableReloadAnimations()
                    }

                default:
                    // Re-enable batched reloads when items are synced.
                    handler?.enableReloadAnimations()
                }
            })
            .disposed(by: disposeBag)
    }

    func process(downloadUpdate update: AttachmentDownloader.Update, toOpen: String?, downloader: AttachmentDownloader?, dataUpdate: (ItemsState.DownloadBatchData?) -> Void, attachmentWillOpen: (AttachmentDownloader.Update) -> Void) {
        if let downloader {
            let batchData = ItemsState.DownloadBatchData(batchData: downloader.batchData)
            dataUpdate(batchData)
        }

        guard !update.kind.isProgress && toOpen == update.key else { return }

        attachmentWillOpen(update)

        switch update.kind {
        case .ready:
            coordinatorDelegate?.showAttachment(key: update.key, parentKey: update.parentKey, libraryId: update.libraryId)

        case .failed(let error):
            coordinatorDelegate?.showAttachmentError(error)

        case .progress, .cancelled:
            break
        }
    }

    // MARK: - To override

    var library: Library {
        return Library(identifier: .custom(.myLibrary), name: "", metadataEditable: false, filesEditable: false)
    }
    
    var collection: Collection {
        return .init(custom: .all)
    }

    var toolbarData: ItemsToolbarController.Data {
        return .init(
            isEditing: false,
            selectedItems: [],
            filters: [],
            downloadBatchData: nil,
            remoteDownloadBatchData: nil,
            identifierLookupBatchData: ItemsState.IdentifierLookupBatchData(saved: 0, total: 0),
            itemCount: 0
        )
    }

    func search(for term: String) {}

    func tagSelectionDidChange(selected: Set<String>) {}

    func process(barButtonItemAction: RightBarButtonItem, sender: UIBarButtonItem) {}

    func downloadsFilterDidChange(enabled: Bool) {}

    // MARK: - Setups

    func setupTitle() {
        title = traitCollection.horizontalSizeClass == .compact ? collection.name : nil
    }

    private func setupSearchBar() {
        let controller = UISearchController(searchResultsController: nil)
        controller.searchBar.placeholder = L10n.Items.searchTitle
        controller.searchBar.rx
            .text.observe(on: MainScheduler.instance)
            .skip(1)
            .debounce(.milliseconds(150), scheduler: MainScheduler.instance)
            .subscribe(onNext: { [weak self] text in
                self?.search(for: text ?? "")
            })
            .disposed(by: disposeBag)
        controller.obscuresBackgroundDuringPresentation = false
        controller.delegate = self
        navigationItem.hidesSearchBarWhenScrolling = false
        navigationItem.searchController = controller
    }

    func setupRightBarButtonItems(expectedItems: [RightBarButtonItem]) {
        let currentItems = (self.navigationItem.rightBarButtonItems ?? []).compactMap({ RightBarButtonItem(rawValue: $0.tag) })
        guard currentItems != expectedItems else { return }
        self.navigationItem.rightBarButtonItems = expectedItems.compactMap({ createRightBarButtonItem($0) }).reversed()

        func createRightBarButtonItem(_ type: RightBarButtonItem) -> UIBarButtonItem? {
            var image: UIImage?
            let title: String
            let accessibilityLabel: String

            switch type {
            case .deselectAll:
                title = L10n.Items.deselectAll
                accessibilityLabel = L10n.Accessibility.Items.deselectAllItems

            case .selectAll:
                title = L10n.Items.selectAll
                accessibilityLabel = L10n.Accessibility.Items.selectAllItems

            case .done:
                title = L10n.done
                accessibilityLabel = L10n.done

            case .select:
                title = L10n.select
                accessibilityLabel = L10n.Accessibility.Items.selectItems

            case .add:
                image = UIImage(systemName: "plus")
                accessibilityLabel = L10n.Items.new
                title = L10n.Items.new

            case .emptyTrash:
                title = L10n.Collections.emptyTrash
                accessibilityLabel = L10n.Collections.emptyTrash
            }

            let primaryAction = UIAction(title: title, image: image) { [weak self] action in
                guard let self, let sender = action.sender as? UIBarButtonItem else { return }
                process(barButtonItemAction: type, sender: sender)
            }
            let item: UIBarButtonItem
            if #available(iOS 26.0.0, *) {
                switch type {
                case .select, .selectAll, .deselectAll, .add, .emptyTrash:
                    item = UIBarButtonItem(primaryAction: primaryAction)

                case .done:
                    item = UIBarButtonItem(systemItem: .done, primaryAction: primaryAction)
                    item.tintColor = Asset.Colors.zoteroBlue.color
                }
            } else {
                item = UIBarButtonItem(primaryAction: primaryAction)
            }
            item.tag = type.rawValue
            item.accessibilityLabel = accessibilityLabel
            return item
        }
    }
}

extension BaseItemsViewController: FiltersDelegate {
    var currentLibrary: Library {
        return library
    }

    func tagOptionsDidChange() {
        updateTagFilter(filters: toolbarData.filters, collectionId: collection.identifier, libraryId: library.identifier)
    }
}

extension BaseItemsViewController: UISearchControllerDelegate {
    func didDismissSearchController(_ searchController: UISearchController) {
        search(for: "")
    }
}
