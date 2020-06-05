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

    @IBOutlet private weak var tableView: UITableView!

    private static let barButtonItemEmptyTag = 1
    private static let barButtonItemSingleTag = 2
    private static let searchBarInTitleViewWindowWidth: CGFloat = 414

    private let viewModel: ViewModel<ItemsActionHandler>
    private let controllers: Controllers
    private let disposeBag: DisposeBag

    private var tableViewHandler: ItemsTableViewHandler!
    private var resultsToken: NotificationToken?
    private weak var searchBarContainer: SearchBarContainer?

    weak var coordinatorDelegate: DetailItemsCoordinatorDelegate?

    init(viewModel: ViewModel<ItemsActionHandler>, controllers: Controllers) {
        self.viewModel = viewModel
        self.controllers = controllers
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
                                                      dragDropController: self.controllers.dragDropController)
        self.setupRightBarButtonItems()
        self.setupToolbar()
        self.setupTitle()
        // Use `navigationController.view.frame` if available, because the navigation controller is already initialized and layed out, so the view
        // size is already calculated properly.
        self.setupSearchBar(for: (self.navigationController?.view.frame.size ?? self.view.frame.size))

        if let results = self.viewModel.state.results {
            self.startObserving(results: results)
        }

        self.tableViewHandler.itemObserver
                             .observeOn(MainScheduler.instance)
                             .subscribe(onNext: { [weak self] item in
                                 self?.showItemDetail(for: item)
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

            // This is a workaround for setting a `navigationItem.searchController` after appearance of this controller on iPad.
            // If `searchController` is set after controller appears on screen, it can create visual artifacts (navigation bar shows second row with
            // nothing in it) or freeze the `tableView` scroll (user has to manually pop back to previous screen and reopen this controller to
            // be able to scroll). The `navigationItem` is fixed when there is a transition to another `UIViewController`. So we fake a transition
            // by pushing empty `UIViewController` and popping back to this one without animation, which fixes everything.
            if position == .navigationItem {
                let controller = UIViewController()
                self.navigationController?.pushViewController(controller, animated: false)
                self.navigationController?.popViewController(animated: false)
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
            self.updateSelectItem(for: state)
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
        }

        if let item = state.itemDuplication {
            self.coordinatorDelegate?.showItemDetail(for: .duplication(item, collectionKey: self.viewModel.state.type.collectionKey),
                                                     library: self.viewModel.state.library)
        }
    }

    // MARK: - Actions

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
            switch changes {
            case .initial:
                self?.tableViewHandler.reload()
            case .update(_, let deletions, let insertions, let modifications):
                self?.tableViewHandler.reload(modifications: modifications, insertions: insertions, deletions: deletions)
            case .error(let error):
                DDLogError("ItemsViewController: could not load results - \(error)")
                self?.viewModel.process(action: .observingFailed)
            }
        })
    }

    private func updateSelectItem(for state: ItemsState) {
        var items = self.navigationItem.rightBarButtonItems ?? []
        items[0] = self.createSelectItem(for: state)
        self.navigationItem.rightBarButtonItems = items
    }

    private func createSelectItem(for state: ItemsState) -> UIBarButtonItem {
        let isEditing = state.isEditing
        let title = isEditing ? L10n.done : L10n.Items.select

        if let selectItem = self.navigationItem.rightBarButtonItems?.first, selectItem.title == title {
            return selectItem
        }

        let item = UIBarButtonItem(title: title, style: .plain, target: nil, action: nil)

        item.rx
            .tap
            .subscribe(onNext: { [weak self] _ in
                if isEditing {
                    self?.viewModel.process(action: .stopEditing)
                } else {
                    self?.viewModel.process(action: .startEditing)
                }
            })
            .disposed(by: self.disposeBag)

        return item
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

    // MARK: - Setups

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

    private func setupRightBarButtonItems() {
        let addItem = UIBarButtonItem(image: UIImage(systemName: "plus"), style: .plain, target: nil, action: nil)
        addItem.rx
               .tap
               .subscribe(onNext: { [weak self] _ in
                   guard let `self` = self else { return }
                   self.coordinatorDelegate?.showAddActions(viewModel: self.viewModel, button: addItem)
               })
               .disposed(by: self.disposeBag)

        let sortItem = UIBarButtonItem(image: UIImage(systemName: "line.horizontal.3.decrease"), style: .plain, target: nil, action: nil)
        sortItem.rx
                .tap
                .subscribe(onNext: { [weak self] _ in
                    guard let `self` = self else { return }
                    self.coordinatorDelegate?.showSortActions(viewModel: self.viewModel, button: sortItem)
                })
                .disposed(by: self.disposeBag)

        let selectItem = self.createSelectItem(for: self.viewModel.state)
        self.navigationItem.rightBarButtonItems = [selectItem, sortItem, addItem]
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
            self?.viewModel.process(action: .trashSelectedItems)
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
                self?.viewModel.process(action: .trashSelectedItems)
            })
            .disposed(by: self.disposeBag)
            removeItem.tag = ItemsViewController.barButtonItemEmptyTag

            items.insert(contentsOf: [spacer, removeItem], at: 2)
        }

        return items
    }

    private func createTrashToolbarItems() -> [UIBarButtonItem] {
        let spacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let trashItem = UIBarButtonItem(image: UIImage(named: "restore_trash"), style: .plain, target: nil, action: nil)
        trashItem.rx.tap.subscribe(onNext: { [weak self] _ in
            self?.viewModel.process(action: .restoreSelectedItems)
        })
        .disposed(by: self.disposeBag)
        trashItem.tag = ItemsViewController.barButtonItemEmptyTag

        let emptyItem = UIBarButtonItem(image: UIImage(named: "empty_trash"), style: .plain, target: nil, action: nil)
        emptyItem.rx.tap.subscribe(onNext: { [weak self] _ in
            self?.viewModel.process(action: .deleteSelectedItems)
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
        let new: SearchBarPosition = windowSize.width <= ItemsViewController.searchBarInTitleViewWindowWidth ? .navigationItem : .titleView

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
    private unowned let searchBar: UISearchBar
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

        self.widthConstraint = self.searchBar.widthAnchor.constraint(equalToConstant: .greatestFiniteMagnitude)
        self.widthConstraint.priority = .defaultLow
        self.widthConstraint.isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: .greatestFiniteMagnitude, height: self.searchBar.bounds.height)
    }

    func freezeWidth() {
        self.widthConstraint.constant = self.searchBar.frame.width
    }

    func unfreezeWidth() {
        self.widthConstraint.constant = .greatestFiniteMagnitude
    }
}
