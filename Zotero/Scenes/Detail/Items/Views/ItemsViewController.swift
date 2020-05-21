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
    @IBOutlet private weak var tableView: UITableView!

    private static let barButtonItemEmptyTag = 1
    private static let barButtonItemSingleTag = 2

    private let viewModel: ViewModel<ItemsActionHandler>
    private let controllers: Controllers
    private let disposeBag: DisposeBag

    private var tableViewHandler: ItemsTableViewHandler!
    private var resultsToken: NotificationToken?

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

        self.navigationItem.rightBarButtonItem = self.rightNavigationBarItem(for: self.viewModel.state)
        self.tableViewHandler = ItemsTableViewHandler(tableView: self.tableView,
                                                      viewModel: self.viewModel,
                                                      dragDropController: self.controllers.dragDropController)
        self.setupToolbar()
        self.setupSearchBar()

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

    // MARK: - UI state

    private func update(state: ItemsState) {
        if state.changes.contains(.editing) {
            self.tableViewHandler.set(editing: state.isEditing, animated: true)
            self.navigationController?.setToolbarHidden(!state.isEditing, animated: true)
            self.navigationItem.rightBarButtonItem = self.rightNavigationBarItem(for: state)
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

    private func rightNavigationBarItem(for state: ItemsState) -> UIBarButtonItem {
        let item: UIBarButtonItem
        if self.viewModel.state.isEditing {
            item = UIBarButtonItem(title: L10n.done, style: .done, target: nil, action: nil)
        } else {
            item = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), style: .plain, target: nil, action: nil)
        }

        item.rx.tap.subscribe(onNext: { [weak self] _ in
            guard let `self` = self else { return }
            if self.viewModel.state.isEditing {
                self.viewModel.process(action: .stopEditing)
            } else {
                self.coordinatorDelegate?.showActionSheet(viewModel: self.viewModel, topInset: self.view.safeAreaInsets.top)
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

    private func setupSearchBar() {
        let searchBar = UISearchBar()
        searchBar.placeholder = L10n.Items.searchTitle
        searchBar.showsCancelButton = true
        self.navigationItem.titleView = searchBar

        searchBar.rx.text.observeOn(MainScheduler.instance)
                         .debounce(.milliseconds(150), scheduler: MainScheduler.instance)
                         .subscribe(onNext: { [weak self] text in
                             self?.viewModel.process(action: .search(text ?? ""))
                         })
                         .disposed(by: self.disposeBag)
    }
}
