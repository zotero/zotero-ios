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
    private enum SearchBarPosition {
        case titleView
        case navigationItem
    }

    private enum RightBarButtonItem: Int {
        case select
        case done
        case selectAll
        case deselectAll
        case add
    }

    private enum OverlayState {
        case processing
        case error(String)
    }

    @IBOutlet private weak var tableView: UITableView!
    @IBOutlet private weak var overlayContainer: UIView!
    @IBOutlet private weak var overlayBody: UIView!
    @IBOutlet private weak var overlayActivityIndicator: UIActivityIndicatorView!
    @IBOutlet private weak var overlayErrorIcon: UIImageView!
    @IBOutlet private weak var overlayText: UILabel!

    private static let itemBatchingLimit = 150

    private let viewModel: ViewModel<ItemsActionHandler>
    private let controllers: Controllers
    private let disposeBag: DisposeBag

    private var tableViewHandler: ItemsTableViewHandler!
    private var toolbarController: ItemsToolbarController!
    private var resultsToken: NotificationToken?
    private weak var searchBarContainer: SearchBarContainer?
    private var searchBarNeedsReset = false
    private weak var webView: WKWebView?

    private weak var coordinatorDelegate: DetailItemsCoordinatorDelegate?

    init(viewModel: ViewModel<ItemsActionHandler>, controllers: Controllers, coordinatorDelegate: DetailItemsCoordinatorDelegate) {
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

        self.tableViewHandler = ItemsTableViewHandler(tableView: self.tableView,
                                                      viewModel: self.viewModel,
                                                      delegate: self,
                                                      dragDropController: self.controllers.dragDropController,
                                                      fileDownloader: self.controllers.userControllers?.fileDownloader,
                                                      schemaController: self.controllers.schemaController)
        self.toolbarController = ItemsToolbarController(viewController: self, initialState: self.viewModel.state, delegate: self)
        self.navigationController?.toolbar.barTintColor = UIColor(dynamicProvider: { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? .black : .white
        })
        self.setupRightBarButtonItems(for: self.viewModel.state)
        self.setupTitle()
        // Use `navigationController.view.frame` if available, because the navigation controller is already initialized and layed out, so the view
        // size is already calculated properly.
        self.setupSearchBar(for: (self.navigationController?.view.frame.size ?? self.view.frame.size))
        self.setupPullToRefresh()
        self.setupFileObservers()
        self.setupAppStateObserver()
        self.setupOverlay()

        self.startObservingSyncProgress()
        if let results = self.viewModel.state.results {
            self.startObserving(results: results)
        }

        self.tableViewHandler.tapObserver
                             .observe(on: MainScheduler.instance)
                             .subscribe(onNext: { [weak self] action in
                                switch action {
                                case .metadata(let item):
                                    self?.showItemDetail(for: item)
                                    self?.resetActiveSearch()
                                case .doi(let doi):
                                    self?.coordinatorDelegate?.show(doi: doi)
                                case .url(let url):
                                    self?.coordinatorDelegate?.showWeb(url: url)
                                case .showAttachmentError(let error, let attachment, let parentKey):
                                    self?.coordinatorDelegate?.showAttachmentError(error, retryAction: { [weak self] in
                                        self?.viewModel.process(action: .openAttachment(attachment: attachment, parentKey: parentKey))
                                    })
                                }
                             })
                             .disposed(by: self.disposeBag)

        self.viewModel.stateObservable
                  .observe(on: MainScheduler.instance)
                  .subscribe(onNext: { [weak self] state in
                      self?.update(state: state)
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

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Workaround for broken `titleView` animation, check `SearchBarContainer` for more info.
        self.searchBarContainer?.freezeWidth()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Workaround for broken `titleView` animation, check `SearchBarContainer` for more info.
        self.searchBarContainer?.unfreezeWidth()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        if UIDevice.current.userInterfaceIdiom == .pad {
            let position = self.setupSearchBar(for: size)
            if position == .navigationItem {
                self.resetSearchBar()
            }
        } else {
            coordinator.animate(alongsideTransition: { _ in
                self.setupSearchBar(for: size)
            }, completion: nil)
        }
    }

    // MARK: - UI state

    private func update(state: ItemsState) {
        if state.changes.contains(.webViewCleanup) {
            self.webView?.removeFromSuperview()
            self.webView = nil
        }

        if state.changes.contains(.results),
           let results = state.results {
            self.startObserving(results: results)
        } else if state.changes.contains(.attachmentsRemoved) {
            self.tableViewHandler.reloadAllAttachments()
        } else if let key = state.updateItemKey {
            self.tableViewHandler.updateCell(with: state.itemAccessories[key], parentKey: key)
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

        if state.changes.contains(.selection) {
            self.setupRightBarButtonItems(for: state)
            self.toolbarController.reloadToolbarItems(for: state)
        }

        if state.changes.contains(.filters) {
            self.toolbarController.reloadToolbarItems(for: state)
        }

        if let key = state.itemKeyToDuplicate {
            self.coordinatorDelegate?.showItemDetail(for: .duplication(itemKey: key, collectionKey: self.viewModel.state.type.collectionKey), library: self.viewModel.state.library)
        }

        if state.processingBibliography {
            self.showOverlay(state: .processing)
        } else if let error = state.bibliographyError {
            if let error = error as? CitationController.Error, error == .styleOrLocaleMissing {
                self.hideOverlay()
                self.coordinatorDelegate?.showMissingStyleError()
            } else {
                self.showOverlay(state: .error(L10n.Errors.Items.generatingBib))
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(1500)) { [weak self] in
                    self?.hideOverlay()
                }
            }
        } else {
            self.hideOverlay()
        }

        if let error = state.error {
            self.process(error: error, state: state)
        }
    }

    private func update(progress: SyncProgress) {
        switch progress {
        case .aborted, .finished:
            self.tableView.refreshControl?.endRefreshing()
        default: break
        }
    }

    func setSearchBarNeedsReset() {
        // Only reset search bar if it's in the title view. It disappears only from the navigation item title view.
        guard self.navigationItem.titleView != nil else { return }
        self.searchBarNeedsReset = true
    }

    // MARK: - Actions

    private func process(error: ItemsError, state: ItemsState) {
        // Perform additional actions for individual errors if needed
        switch error {
        case .itemMove, .deletion, .deletionFromCollection:
            if let snapshot = state.results {
                self.tableViewHandler.reloadAll(snapshot: snapshot.freeze())
            }
        case .dataLoading, .collectionAssignment, .noteSaving, .attachmentAdding(_), .duplicationLoading: break
        }

        // Show appropriate message
        self.coordinatorDelegate?.show(error: error)
    }

    private func showOverlay(state: OverlayState) {
        switch state {
        case .processing:
            self.overlayText.text = L10n.Items.generatingBib
            self.overlayActivityIndicator.isHidden = false
            self.overlayActivityIndicator.startAnimating()
            self.overlayErrorIcon.isHidden = true

        case .error(let message):
            self.overlayText.text = message
            self.overlayActivityIndicator.stopAnimating()
            self.overlayErrorIcon.isHidden = false
        }

        self.overlayContainer.layoutIfNeeded()

        guard self.overlayContainer.isHidden else { return }

        self.overlayContainer.alpha = 0
        self.overlayContainer.isHidden = false

        UIView.animate(withDuration: 0.2) {
            self.overlayContainer.alpha = 1
        }
    }

    private func hideOverlay() {
        guard !self.overlayContainer.isHidden else { return }

        UIView.animate(withDuration: 0.2) {
            self.overlayContainer.alpha = 0
        } completion: { finished in
            guard finished else { return }
            self.overlayContainer.isHidden = true
        }
    }

    private func process(action: ItemAction.Kind, for selectedKeys: Set<String>, button: UIBarButtonItem?, completionAction: ((Bool) -> Void)?) {
        switch action {
        case .addToCollection:
            guard !selectedKeys.isEmpty else { return }
            self.coordinatorDelegate?.showCollectionPicker(in: self.viewModel.state.library, completed: { [weak self] collections in
                self?.viewModel.process(action: .assignItemsToCollections(items: selectedKeys, collections: collections))
                completionAction?(true)
            })

        case .createParent:
            guard let key = selectedKeys.first, case .attachment(let attachment) = self.viewModel.state.itemAccessories[key] else { return }
            self.coordinatorDelegate?.showItemDetail(for: .creation(type: ItemTypes.document, child: attachment, collectionKey: nil), library: self.viewModel.state.library)

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
            self.coordinatorDelegate?.showFilters(viewModel: self.viewModel, button: button)

        case .sort:
            guard let button = button else { return }
            self.coordinatorDelegate?.showSortActions(viewModel: self.viewModel, button: button)

        case .share:
            guard !selectedKeys.isEmpty else { return }
            self.coordinatorDelegate?.showCiteExport(for: selectedKeys, libraryId: self.viewModel.state.library.identifier)

        case .copyBibliography:
            let webView = WKWebView()
            webView.isHidden = true
            self.view.insertSubview(webView, at: 0)
            self.webView = webView

            self.viewModel.process(action: .quickCopyBibliography(selectedKeys, self.viewModel.state.library.identifier, webView))

        case .copyCitation:
            self.coordinatorDelegate?.showCitation(for: selectedKeys, libraryId: self.viewModel.state.library.identifier)

        case .download:
            self.viewModel.process(action: .download(selectedKeys))

        case .removeDownload:
            self.viewModel.process(action: .removeDownloads(selectedKeys))
        }
    }

    // This is a workaround for setting a `navigationItem.searchController` after appearance of this controller on iPad.
    // If `searchController` is set after controller appears on screen, it can create visual artifacts (navigation bar shows second row with
    // nothing in it) or freeze the `tableView` scroll (user has to manually pop back to previous screen and reopen this controller to
    // be able to scroll). The `navigationItem` is fixed when there is a transition to another `UIViewController`. So we fake a transition
    // by pushing empty `UIViewController` and popping back to this one without animation, which fixes everything.
    private func resetSearchBar() {
        let controller = UIViewController()
        self.navigationController?.pushViewController(controller, animated: false)
        self.navigationController?.popViewController(animated: false)
    }

    private func resetActiveSearch() {
        if let searchBar = self.searchBarContainer?.searchBar {
            searchBar.resignFirstResponder()
        } else if let controller = self.navigationItem.searchController {
            controller.searchBar.resignFirstResponder()
        }
    }

    private func showItemDetail(for item: RItem) {
        switch item.rawType {
        case ItemTypes.note:
            guard let note = Note(item: item) else { return }
            let tags = Array(item.tags.map({ Tag(tag: $0) }))
            let library = self.viewModel.state.library
            self.coordinatorDelegate?.showNote(with: note.text, tags: tags, title: nil, libraryId: library.identifier, readOnly: !library.metadataEditable, save: { [weak self] newText, newTags in
                self?.viewModel.process(action: .saveNote(note.key, newText, newTags))
            })

        default:
            self.coordinatorDelegate?.showItemDetail(for: .preview(key: item.key), library: self.viewModel.state.library)
        }
    }

    private func startObserving(results: Results<RItem>) {
        self.resultsToken = results.observe(keyPaths: RItem.observableKeypathsForItemList, { [weak self] changes  in
            guard let `self` = self else { return }

            switch changes {
            case .initial(let objects):
                self.tableViewHandler.reloadAll(snapshot: objects.freeze())
            case .update(let results, let deletions, let insertions, let modifications):
                let correctedModifications = Database.correctedModifications(from: modifications, insertions: insertions, deletions: deletions)
                self.viewModel.process(action: .updateKeys(items: results, deletions: deletions, insertions: insertions, modifications: correctedModifications))
                self.tableViewHandler.reload(snapshot: results.freeze(), modifications: modifications, insertions: insertions, deletions: deletions)
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
                guard let `self` = self else { return }
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
                break
                }
            })
            .disposed(by: self.disposeBag)
    }

    @objc private func startSync() {
        guard let scheduler = self.controllers.userControllers?.syncScheduler, !scheduler.syncController.inProgress else { return }
        scheduler.request(syncType: .ignoreIndividualDelays)
    }

    // MARK: - Setups

    private func setupAppStateObserver() {
        NotificationCenter.default
                          .rx
                          .notification(.willEnterForeground)
                          .observe(on: MainScheduler.instance)
                          .subscribe(onNext: { [weak self] _ in
                              guard let `self` = self else { return }
                              if self.searchBarNeedsReset {
                                  self.resetSearchBar()
                                  self.searchBarNeedsReset = false
                              }
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

        guard let downloader = self.controllers.userControllers?.fileDownloader else { return }

        downloader.observable
            .observe(on: MainScheduler.instance)
            .subscribe(with: self, onNext: { `self`, update in
                self.viewModel.process(action: .updateDownload(update))

                switch update.kind {
                case .ready:
                    if self.viewModel.state.attachmentToOpen == update.key {
                        self.viewModel.process(action: .attachmentOpened(update.key))
                        self.coordinatorDelegate?.showAttachment(key: update.key, parentKey: update.parentKey, libraryId: update.libraryId)
                    }
                default: break
                }
            })
            .disposed(by: self.disposeBag)
    }

    private func setupTitle() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }

        switch self.viewModel.state.type {
        case .all:
            self.title = L10n.Collections.allItems
        case .publications:
            self.title = L10n.Collections.myPublications
        case .trash:
            self.title = L10n.Collections.trash
        case .collection(_, let name):
            self.title = name
        case .search(_, let name):
            self.title = name
        }
    }

    private func setupRightBarButtonItems(for state: ItemsState) {
        let currentItems = (self.navigationItem.rightBarButtonItems ?? []).compactMap({ RightBarButtonItem(rawValue: $0.tag) })
        let expectedItems = self.rightBarButtonItemTypes(for: state)
        guard currentItems != expectedItems else { return }
        self.navigationItem.rightBarButtonItems = expectedItems.map({ self.createRightBarButtonItem($0) }).reversed()
    }

    private func rightBarButtonItemTypes(for state: ItemsState) -> [RightBarButtonItem] {
        if !state.isEditing {
            return [.add, .select]
        }
        let allSelected = state.selectedItems.count == (state.results?.count ?? 0)
        if allSelected {
            return [.add, .deselectAll, .done]
        }
        return [.add, .selectAll, .done]
    }

    private func createRightBarButtonItem(_ type: RightBarButtonItem) -> UIBarButtonItem {
        var image: UIImage?
        var title: String?
        let action: (UIBarButtonItem) -> Void
        let accessibilityLabel: String

        switch type {
        case .deselectAll:
            title = L10n.Items.deselectAll
            accessibilityLabel = L10n.Accessibility.Items.deselectAllItems
            action = { [weak self] _ in
                self?.viewModel.process(action: .toggleSelectionState)
            }
        case .selectAll:
            title = L10n.Items.selectAll
            accessibilityLabel = L10n.Accessibility.Items.selectAllItems
            action = { [weak self] _ in
                self?.viewModel.process(action: .toggleSelectionState)
            }
        case .done:
            title = L10n.done
            accessibilityLabel = L10n.done
            action = { [weak self] _ in
                self?.viewModel.process(action: .stopEditing)
            }
        case .select:
            title = L10n.Items.select
            accessibilityLabel = L10n.Accessibility.Items.selectItems
            action = { [weak self] _ in
                self?.viewModel.process(action: .startEditing)
            }
        case .add:
            image = UIImage(systemName: "plus")
            accessibilityLabel = L10n.Items.new
            title = nil
            action = { [weak self] item in
                guard let `self` = self else { return }
                self.coordinatorDelegate?.showAddActions(viewModel: self.viewModel, button: item)
            }
        }

        let item: UIBarButtonItem
        if let title = title {
            item = UIBarButtonItem(title: title, style: .plain, target: nil, action: nil)
        } else if let image = image {
            item = UIBarButtonItem(image: image, style: .plain, target: nil, action: nil)
        } else {
            fatalError("ItemsViewController: you need a title or image!")
        }

        item.tag = type.rawValue
        item.accessibilityLabel = accessibilityLabel
        item.rx.tap.subscribe(onNext: { _ in action(item) }).disposed(by: self.disposeBag)
        return item
    }

    /// Setup `searchBar` for current window size. If there is enough space for the `searchBar` in `titleView`, it's added there, otherwise it's added
    /// to `navigationItem`, where it appears under `navigationBar`.
    /// - parameter windowSize: Current window size.
    /// - returns: New search bar position
    @discardableResult
    private func setupSearchBar(for windowSize: CGSize) -> SearchBarPosition {
        // Detect current position of search bar
        let current: SearchBarPosition? = self.navigationItem.searchController != nil ? .navigationItem :
                                                                                        (self.navigationItem.titleView != nil ? .titleView : nil)
        // The search bar can change position based on current window size. If the window is too narrow, the search bar appears in
        // navigationItem, otherwise it can appear in titleView.
        let new: SearchBarPosition = UIDevice.current.isCompactWidth(size: windowSize) ? .navigationItem : .titleView

        // Only change search bar if the position changes.
        guard current != new else { return new }

        self.removeSearchBar()
        self.setupSearchBar(in: new)

        return new
    }

    /// Setup `searchBar` in given position.
    /// - parameter position: Position of `searchBar`.
    private func setupSearchBar(in position: SearchBarPosition) {
        switch position {
        case .titleView:
            let searchBar = UISearchBar()
            self.setup(searchBar: searchBar)
            // Workaround for broken `titleView` animation, check `SearchBarContainer` for more info.
            let container = SearchBarContainer(searchBar: searchBar)
            self.navigationItem.titleView = container
            self.searchBarContainer = container

        case .navigationItem:
            let controller = UISearchController(searchResultsController: nil)
            self.setup(searchBar: controller.searchBar)
            controller.obscuresBackgroundDuringPresentation = false
            if UIDevice.current.userInterfaceIdiom == .phone {
                self.navigationItem.hidesSearchBarWhenScrolling = false
            }
            self.navigationItem.searchController = controller
        }
    }

    /// Setup `searchBar`, start observing text changes.
    /// - parameter searchBar: `searchBar` to setup and observe.
    private func setup(searchBar: UISearchBar) {
        searchBar.placeholder = L10n.Items.searchTitle
        searchBar.rx.text.observe(on: MainScheduler.instance)
                         .debounce(.milliseconds(150), scheduler: MainScheduler.instance)
                         .subscribe(onNext: { [weak self] text in
                             self?.viewModel.process(action: .search(text ?? ""))
                         })
                         .disposed(by: self.disposeBag)
    }

    /// Removes `searchBar` from all positions.
    private func removeSearchBar() {
        if self.navigationItem.searchController != nil {
            self.navigationItem.searchController = nil
        }
        if self.navigationItem.titleView != nil {
            self.navigationItem.titleView = nil
        }
        self.searchBarContainer = nil
    }

    private func setupPullToRefresh() {
        let control = UIRefreshControl()
        control.addTarget(self, action: #selector(ItemsViewController.startSync), for: .valueChanged)
        self.tableView.refreshControl = control

        self.setupSyncObserving()
    }

    private func setupSyncObserving() {
        guard let scheduler = self.controllers.userControllers?.syncScheduler else { return }
        scheduler.syncController
                 .progressObservable
                 .observe(on: MainScheduler.instance)
                 .subscribe(onNext: { [weak self] progress in
                     self?.update(progress: progress)
                 })
                 .disposed(by: self.disposeBag)
    }

    private func setupOverlay() {
        self.overlayBody.layer.cornerRadius = 16
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
    func attachment(for key: String, parentKey: String?, libraryId: LibraryIdentifier) -> (Attachment, Library, UIView, CGRect?)? {
        guard let accessory = self.viewModel.state.itemAccessories[parentKey ?? key], let attachment = accessory.attachment else { return nil }
        let (sourceView, sourceRect) = self.tableViewHandler.sourceDataForCell(for: (parentKey ?? key))
        return (attachment, self.viewModel.state.library, sourceView, sourceRect)
    }
}

extension ItemsViewController: ItemsToolbarControllerDelegate {
    func process(action: ItemAction.Kind, button: UIBarButtonItem) {
        self.process(action: action, for: self.viewModel.state.selectedItems, button: button, completionAction: nil)
    }
}

///
/// This is a conainer for `UISearchBar` to fix broken UIKit `titleView` animation in navigation bar.
/// The `titleView` is assigned an expanding view (`UISearchBar`), so the `titleView` expands to full width on animation to different screen.
/// For example, if the new screen has fewer `rightBarButtonItems`, the `titleView` width expands and the animation looks as if the search bar is
/// moving to the right, even though the screen is animating out to the left.
///
/// To fix this, the `titleView` needs to have a set width. I didn't want to use hardcoded values and calculate the available `titleView` width
/// manually, so I created this view.
///
/// The point is that this view is expandable (`intrinsicContentSize` width set to `.greatestFiniteMagnitude`). The child `searchBar` has trailing
/// constraint less or equal than trailing constraint of parent `SearchBarContainer`. But the width constraint of search bar is set to
/// `.greatestFiniteMagnitude` with low priority. So by default the search bar expands as much as possible, but is limited by parent width.
/// Then, when parent controller is leaving screen on `viewWillDisappear` it calls `freezeWidth()` to freeze the search bar width by setting width
/// constraint to current width of search bar. When the animation finishes the parent controller has to call `unfreezeWidth()` to set the width back
/// to `.greatestFiniteMagnitude`, so that it stretches to appropriate size when needed (for example when the device rotates).
///
fileprivate final class SearchBarContainer: UIView {
    unowned let searchBar: UISearchBar
    private var widthConstraint: NSLayoutConstraint!

    init(searchBar: UISearchBar) {
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        self.searchBar = searchBar

        super.init(frame: CGRect())

        self.addSubview(searchBar)

        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: self.topAnchor),
            searchBar.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            searchBar.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            searchBar.trailingAnchor.constraint(lessThanOrEqualTo: self.trailingAnchor)
        ])

        let maxSize = max(UIScreen.main.bounds.size.width, UIScreen.main.bounds.size.height)
        self.widthConstraint = self.searchBar.widthAnchor.constraint(equalToConstant: maxSize)
        self.widthConstraint.priority = .defaultLow
        self.widthConstraint.isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        // Changed from .greatestFiniteValue to this because of error "This NSLayoutConstraint is being configured with a constant that exceeds
        // internal limits." This works fine as well and the debugger doesn't show the error anymore.
        let maxSize = max(UIScreen.main.bounds.size.width, UIScreen.main.bounds.size.height)
        return CGSize(width: maxSize, height: self.searchBar.bounds.height)
    }

    func freezeWidth() {
        self.widthConstraint.constant = self.searchBar.frame.width
    }

    func unfreezeWidth() {
        self.widthConstraint.constant = .greatestFiniteMagnitude
    }
}
