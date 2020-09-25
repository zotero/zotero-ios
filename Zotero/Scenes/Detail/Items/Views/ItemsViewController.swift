//
//  ItemsViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 17/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjack
import RealmSwift
import RxSwift

class ItemsViewController: UIViewController {
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
        case sort
    }

    @IBOutlet private weak var tableView: UITableView!

    private static let barButtonItemEmptyTag = 1
    private static let barButtonItemSingleTag = 2

    private let viewModel: ViewModel<ItemsActionHandler>
    private let controllers: Controllers
    private let disposeBag: DisposeBag

    private var tableViewHandler: ItemsTableViewHandler!
    private var resultsToken: NotificationToken?
    private weak var searchBarContainer: SearchBarContainer?
    private var searchBarNeedsReset = false

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
                                                      dragDropController: self.controllers.dragDropController,
                                                      fileDownloader: self.controllers.userControllers?.fileDownloader)
        self.setupRightBarButtonItems(for: self.viewModel.state)
        self.setupToolbar()
        self.setupTitle()
        // Use `navigationController.view.frame` if available, because the navigation controller is already initialized and layed out, so the view
        // size is already calculated properly.
        self.setupSearchBar(for: (self.navigationController?.view.frame.size ?? self.view.frame.size))
        self.setupFileObservers()
        self.setupAppStateObserver()

        if let results = self.viewModel.state.results {
            self.startObserving(results: results)
        }

        self.tableViewHandler.tapObserver
                             .observeOn(MainScheduler.instance)
                             .subscribe(onNext: { [weak self] item in
                                self?.showItemDetail(for: item)
                                self?.resetActiveSearch()
                             })
                             .disposed(by: self.disposeBag)

        self.viewModel.stateObservable
                  .observeOn(MainScheduler.instance)
                  .subscribe(onNext: { [weak self] state in
                      self?.update(state: state)
                  })
                  .disposed(by: self.disposeBag)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Workaround for broken `titleView` animation, check `SearchBarContainer` for more info.
        self.searchBarContainer?.freezeWidth()
        self.tableViewHandler?.pauseReloading()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Workaround for broken `titleView` animation, check `SearchBarContainer` for more info.
        self.searchBarContainer?.unfreezeWidth()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.tableViewHandler.resumeReloading()
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
        if state.changes.contains(.editing) {
            self.tableViewHandler.set(editing: state.isEditing, animated: true)
            self.navigationController?.setToolbarHidden(!state.isEditing, animated: true)
            self.setupRightBarButtonItems(for: state)
        }

        if state.changes.contains(.results),
           let results = state.results {
            self.startObserving(results: results)
        }

        if state.changes.contains(.sortType) {
            self.tableViewHandler.reload()
        }

        if state.changes.contains(.selection) {
            self.updateToolbarItems()
            self.setupRightBarButtonItems(for: state)
        }

        if state.changes.contains(.selectAll) {
            if state.selectedItems.isEmpty {
                self.tableViewHandler.deselectAll()
            } else {
                self.tableViewHandler.selectAll()
            }
        }

        if state.changes.contains(.attachmentsRemoved) {
            self.tableViewHandler.reload()
        }

        if let (attachment, parentKey) = state.openAttachment {
            self.open(attachment: attachment, parentKey: parentKey)
        }

        if let key = state.updateItemKey {
            let attachment = state.attachments[key]
            self.tableViewHandler.updateCell(with: attachment, parentKey: key)
        }

        if let item = state.itemDuplication {
            self.coordinatorDelegate?.showItemDetail(for: .duplication(item, collectionKey: self.viewModel.state.type.collectionKey),
                                                     library: self.viewModel.state.library)
        }
    }

    func setSearchBarNeedsReset() {
        // Only reset search bar if it's in the title view. It disappears only from the navigation item title view.
        guard self.navigationItem.titleView != nil else { return }
        self.searchBarNeedsReset = true
    }

    // MARK: - Actions

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
            searchBar.text = nil
            searchBar.resignFirstResponder()
        } else if let controller = self.navigationItem.searchController {
            controller.isActive = false
        }
    }

    private func open(attachment: Attachment, parentKey: String) {
        let (sourceView, sourceRect) = self.tableViewHandler.sourceDataForCell(for: parentKey)
        self.coordinatorDelegate?.show(attachment: attachment, library: self.viewModel.state.library, sourceView: sourceView, sourceRect: sourceRect)
    }

    private func showItemDetail(for item: RItem) {
        switch item.rawType {
        case ItemTypes.note:
            guard let note = Note(item: item) else { return }
            self.coordinatorDelegate?.showNote(with: note.text, readOnly: !self.viewModel.state.library.metadataEditable, save: { [weak self] newText in
                self?.viewModel.process(action: .saveNote(note.key, newText))
            })

        default:
            self.coordinatorDelegate?.showItemDetail(for: .preview(item), library: self.viewModel.state.library)
        }
    }

    private func startObserving(results: Results<RItem>) {
        self.resultsToken = results.observe({ [weak self] changes  in
            guard let `self` = self else { return }

            switch changes {
            case .initial:
                self.tableViewHandler.reload()
            case .update(let results, let deletions, let insertions, let modifications):
                let correctedModifications = Database.correctedModifications(from: modifications, insertions: insertions, deletions: deletions)
                let items = (insertions + correctedModifications).map({ results[$0] })
                self.viewModel.process(action: .cacheAttachmentUpdates(items: items))
                self.tableViewHandler.reload(modifications: modifications, insertions: insertions, deletions: deletions)
            case .error(let error):
                DDLogError("ItemsViewController: could not load results - \(error)")
                self.viewModel.process(action: .observingFailed)
            }
        })
    }

    private func updateToolbarItems() {
        self.toolbarItems?.forEach({ item in
            switch item.tag {
            case ItemsViewController.barButtonItemEmptyTag:
                item.isEnabled = !self.viewModel.state.selectedItems.isEmpty
            case ItemsViewController.barButtonItemSingleTag:
                item.isEnabled = self.viewModel.state.selectedItems.count == 1
            default: break
            }
        })
    }

    private func ask(question: String, title: String, isDestructive: Bool, confirm: @escaping () -> Void) {
        let controller = UIAlertController(title: title, message: question, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.yes, style: (isDestructive ? .destructive : .default), handler: { _ in
            confirm()
        }))
        controller.addAction(UIAlertAction(title: L10n.no, style: .cancel, handler: nil))
        self.present(controller, animated: true, completion: nil)
    }

    // MARK: - Setups

    private func setupAppStateObserver() {
        NotificationCenter.default
                          .rx
                          .notification(.willEnterForeground)
                          .observeOn(MainScheduler.instance)
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
                          .observeOn(MainScheduler.instance)
                          .subscribe(onNext: { [weak self] notification in
                              if let notification = notification.object as? AttachmentFileDeletedNotification {
                                  self?.viewModel.process(action: .updateAttachments(notification))
                              }
                          })
                          .disposed(by: self.disposeBag)

        guard let downloader = self.controllers.userControllers?.fileDownloader else { return }

        downloader.observable
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: { [weak self] update in
                self?.viewModel.process(action: .updateDownload(update))
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
            return [.add, .sort, .select]
        }
        let allSelected = state.selectedItems.count == (state.results?.count ?? 0)
        if allSelected {
            return [.sort, .deselectAll, .done]
        }
        return [.sort, .selectAll, .done]
    }

    private func createRightBarButtonItem(_ type: RightBarButtonItem) -> UIBarButtonItem {
        var image: UIImage?
        var title: String?
        let action: (UIBarButtonItem) -> Void

        switch type {
        case .deselectAll:
            title = L10n.Items.deselectAll
            action = { [weak self] _ in
                self?.viewModel.process(action: .toggleSelectionState)
            }
        case .selectAll:
            title = L10n.Items.selectAll
            action = { [weak self] _ in
                self?.viewModel.process(action: .toggleSelectionState)
            }
        case .done:
            title = L10n.done
            action = { [weak self] _ in
                self?.viewModel.process(action: .stopEditing)
            }
        case .select:
            title = L10n.Items.select
            action = { [weak self] _ in
                self?.viewModel.process(action: .startEditing)
            }
        case .sort:
            image = UIImage(systemName: "line.horizontal.3.decrease")
            title = nil
            action = { [weak self] item in
                guard let `self` = self else { return }
                self.coordinatorDelegate?.showSortActions(viewModel: self.viewModel, button: item)
            }
        case .add:
            image = UIImage(systemName: "plus")
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
        item.rx.tap.subscribe(onNext: { _ in action(item) }).disposed(by: self.disposeBag)
        return item
    }

    private func setupToolbar() {
        self.toolbarItems = self.viewModel.state.type.isTrash ? self.createTrashToolbarItems() : self.createNormalToolbarItems()
    }

    private func createNormalToolbarItems() -> [UIBarButtonItem] {
        let pickerItem = UIBarButtonItem(image: UIImage(systemName: "folder.badge.plus"), style: .plain, target: nil, action: nil)
        pickerItem.rx.tap.subscribe(onNext: { [weak self] _ in
            guard let `self` = self else { return }
            let binding = self.viewModel.binding(keyPath: \.selectedItems, action: { .assignSelectedItemsToCollections($0) })
            self.coordinatorDelegate?.showCollectionPicker(in: self.viewModel.state.library, selectedKeys: binding)
        })
        .disposed(by: self.disposeBag)
        pickerItem.tag = ItemsViewController.barButtonItemEmptyTag

        let trashItem = UIBarButtonItem(image: UIImage(systemName: "trash"), style: .plain, target: nil, action: nil)
        trashItem.rx.tap.subscribe(onNext: { [weak self] _ in
            let question = self?.viewModel.state.selectedItems.count == 1 ? L10n.Items.trashQuestion : L10n.Items.trashMultipleQuestion
            self?.ask(question: question, title: L10n.Items.trashTitle, isDestructive: false, confirm: {
                self?.viewModel.process(action: .trashSelectedItems)
            })
        })
        .disposed(by: self.disposeBag)
        trashItem.tag = ItemsViewController.barButtonItemEmptyTag

        let duplicateItem = UIBarButtonItem(image: UIImage(systemName: "square.on.square"), style: .plain, target: nil, action: nil)
        duplicateItem.rx.tap.subscribe(onNext: { [weak self] _ in
            if let key = self?.viewModel.state.selectedItems.first {
                self?.viewModel.process(action: .loadItemToDuplicate(key))
            }
        })
        .disposed(by: self.disposeBag)
        duplicateItem.tag = ItemsViewController.barButtonItemSingleTag

        let spacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)

        var items = [spacer, pickerItem, spacer, trashItem, spacer, duplicateItem, spacer]

        if self.viewModel.state.type.collectionKey != nil {
            let removeItem = UIBarButtonItem(image: UIImage(systemName: "folder.badge.minus"), style: .plain, target: nil, action: nil)
            removeItem.rx.tap.subscribe(onNext: { [weak self] _ in
                let question = self?.viewModel.state.selectedItems.count == 1 ? L10n.Items.removeFromCollectionQuestion :
                                                                                L10n.Items.removeFromCollectionMultipleQuestion
                self?.ask(question: question, title: L10n.Items.removeFromCollectionTitle, isDestructive: false, confirm: {
                    self?.viewModel.process(action: .deleteSelectedItemsFromCollection)
                })
            })
            .disposed(by: self.disposeBag)
            removeItem.tag = ItemsViewController.barButtonItemEmptyTag

            items.insert(contentsOf: [spacer, removeItem], at: 2)
        }

        return items
    }

    private func createTrashToolbarItems() -> [UIBarButtonItem] {
        let spacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let trashItem = UIBarButtonItem(image: Asset.Images.restoreTrash.image, style: .plain, target: nil, action: nil)
        trashItem.rx.tap.subscribe(onNext: { [weak self] _ in
            let question = self?.viewModel.state.selectedItems.count == 1 ? L10n.Items.restoreQuestion : L10n.Items.restoreMultipleQuestion
            self?.ask(question: question, title: L10n.Items.restoreQuestion, isDestructive: false, confirm: {
                self?.viewModel.process(action: .restoreSelectedItems)
            })
        })
        .disposed(by: self.disposeBag)
        trashItem.tag = ItemsViewController.barButtonItemEmptyTag

        let emptyItem = UIBarButtonItem(image: Asset.Images.emptyTrash.image, style: .plain, target: nil, action: nil)
        emptyItem.rx.tap.subscribe(onNext: { [weak self] _ in
            let question = self?.viewModel.state.selectedItems.count == 1 ? L10n.Items.deleteQuestion : L10n.Items.deleteMultipleQuestion
            self?.ask(question: question, title: L10n.delete, isDestructive: true, confirm: {
                self?.viewModel.process(action: .deleteSelectedItems)
            })
        })
        .disposed(by: self.disposeBag)
        emptyItem.tag = ItemsViewController.barButtonItemEmptyTag

        return [spacer, trashItem, spacer, emptyItem, spacer]
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
        searchBar.rx.text.observeOn(MainScheduler.instance)
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
fileprivate class SearchBarContainer: UIView {
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
