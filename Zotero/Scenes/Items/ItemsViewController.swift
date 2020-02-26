//
//  ItemsViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 17/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import MobileCoreServices
import UIKit
import SwiftUI

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
    private var overlaySink: AnyCancellable?
    private var resultsToken: NotificationToken?

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

        self.definesPresentationContext = true
        self.navigationItem.rightBarButtonItem = self.rightNavigationBarItem(for: self.viewModel.state)
        self.tableViewHandler = ItemsTableViewHandler(tableView: self.tableView,
                                                      viewModel: self.viewModel,
                                                      dragDropController: self.controllers.dragDropController)
        self.setupToolbar()

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

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        // Set the search controller here so that it doesn't appear initially
        if self.navigationItem.searchController == nil {
            self.setupSearchController()
        }
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
            self.showItemDetail(for: .duplication(item, collectionKey: self.viewModel.state.type.collectionKey))
        }
    }

    // MARK: - Actions

    private func perform(overlayAction: ItemsActionSheetView.Action) {
        var shouldDismiss = true
        
        switch overlayAction {
        case .dismiss: break
        case .showAttachmentPicker:
            self.showAttachmentPicker()
        case .showItemCreation:
            self.showItemCreation()
        case .showNoteCreation:
            self.showNoteCreation()
        case .showSortTypePicker:
            self.presentSortTypePicker()
        case .startEditing:
            self.viewModel.process(action: .startEditing)
        case .toggleSortOrder:
            self.viewModel.process(action: .toggleSortOrder)
            shouldDismiss = false
        }

        if shouldDismiss {
            self.dismiss(animated: true, completion: nil)
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
            item = UIBarButtonItem(title: "Done", style: .done, target: nil, action: nil)
        } else {
            item = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), style: .plain, target: nil, action: nil)
        }

        item.rx.tap.subscribe(onNext: { [weak self] _ in
            guard let `self` = self else { return }
            if self.viewModel.state.isEditing {
                self.viewModel.process(action: .stopEditing)
            } else {
                self.showActionSheet()
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

    // MARK: - Navigation

    private func presentSortTypePicker() {
        let binding: Binding<ItemsSortType.Field> = Binding(get: {
            return self.viewModel.state.sortType.field
        }) { value in
            self.viewModel.process(action: .setSortField(value))
        }
        let view = ItemSortTypePickerView(sortBy: binding,
                                          closeAction: { [weak self] in
                                              self?.dismiss(animated: true, completion: nil)
                                          })
        let navigationController = UINavigationController(rootViewController: UIHostingController(rootView: view))
        navigationController.isModalInPresentation = true
        self.present(navigationController, animated: true, completion: nil)
    }

    private func showNoteEditing(for note: Note) {
        self.presentNoteEditor(with: note.text) { [weak self] text in
            self?.viewModel.process(action: .saveNote(note.key, text))
        }
    }

    private func showNoteCreation() {
        self.presentNoteEditor(with: "") { [weak self] text in
            self?.viewModel.process(action: .saveNote(nil, text))
        }
    }

    private func presentNoteEditor(with text: String, save: @escaping (String) -> Void) {
        let controller = NoteEditorViewController(text: text, saveAction: save)
        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.isModalInPresentation = true
        self.present(navigationController, animated: true, completion: nil)
    }

    private func showAttachmentPicker() {
        let documentTypes = [String(kUTTypePDF), String(kUTTypePNG), String(kUTTypeJPEG)]
        let controller = DocumentPickerViewController(documentTypes: documentTypes, in: .import)
        controller.popoverPresentationController?.sourceView = self.view
        controller.observable
                  .observeOn(MainScheduler.instance)
                  .subscribe(onNext: { [weak self] urls in
                      self?.viewModel.process(action: .addAttachments(urls))
                  })
                  .disposed(by: self.disposeBag)
        self.present(controller, animated: true, completion: nil)
    }

    private func showCollectionPicker() {
        guard let dbStorage = self.controllers.userControllers?.dbStorage else { return }

        let view = CollectionsPickerView(selectedKeys: { [weak self] keys in
                                             self?.viewModel.process(action: .assignSelectedItemsToCollections(keys))
                                         },
                                         closeAction: { [weak self] in
                                             self?.dismiss(animated: true, completion: nil)
                                         })
                        .environmentObject(CollectionPickerStore(library: self.viewModel.state.library, excludedKeys: [], dbStorage: dbStorage))

        let navigationController = UINavigationController(rootViewController: UIHostingController(rootView: view))
        navigationController.isModalInPresentation = true
        self.present(navigationController, animated: true, completion: nil)
    }

    private func showItemCreation() {
        self.showItemDetail(for: .creation(libraryId: self.viewModel.state.library.identifier,
                                           collectionKey: self.viewModel.state.type.collectionKey,
                                           filesEditable: self.viewModel.state.library.filesEditable))
    }

    private func showItemDetail(for item: RItem) {
        switch item.rawType {
        case ItemTypes.note:
            if let note = Note(item: item) {
                self.showNoteEditing(for: note)
            }

        default:
            self.showItemDetail(for: .preview(item))
        }
    }

    private func showItemDetail(for type: ItemDetailState.DetailType) {
        guard let dbStorage = self.controllers.userControllers?.dbStorage else { return }

        do {
            let data = try ItemDetailDataCreator.createData(from: type,
                                                            schemaController: self.controllers.schemaController,
                                                            fileStorage: self.controllers.fileStorage)
            let state = ItemDetailState(type: type, userId: Defaults.shared.userId, data: data)
            let handler = ItemDetailActionHandler(apiClient: self.controllers.apiClient,
                                                  fileStorage: self.controllers.fileStorage,
                                                  dbStorage: dbStorage,
                                                  schemaController: self.controllers.schemaController)
            let viewModel = ViewModel(initialState: state, handler: handler)

            let hidesBackButton: Bool
            switch type {
            case .preview:
                hidesBackButton = false
            case .creation, .duplication:
                hidesBackButton = true
            }

            let controller = ItemDetailViewController(viewModel: viewModel, controllers: self.controllers)
            if hidesBackButton {
                controller.navigationItem.setHidesBackButton(true, animated: false)
            }
            self.navigationController?.pushViewController(controller, animated: true)
        } catch let error {
            // TODO: - show error
        }
    }

    private func showActionSheet() {
        let view = ItemsActionSheetView(sortType: self.viewModel.state.sortType)
        self.overlaySink = view.actionObserver.sink { [weak self] action in
            self?.perform(overlayAction: action)
        }

        let controller = UIHostingController(rootView: view)
        controller.view.backgroundColor = .clear
        controller.modalPresentationStyle = .overCurrentContext
        controller.modalTransitionStyle = .crossDissolve
        self.present(controller, animated: true, completion: nil)
    }

    // MARK: - Setups

    private func setupToolbar() {
        self.toolbarItems = self.viewModel.state.type.isTrash ? self.createTrashToolbarItems() : self.createNormalToolbarItems()
    }

    private func createNormalToolbarItems() -> [UIBarButtonItem] {
        let pickerItem = UIBarButtonItem(image: UIImage(systemName: "folder.badge.plus"), style: .plain, target: nil, action: nil)
        pickerItem.rx.tap.subscribe(onNext: { [weak self] _ in
            self?.showCollectionPicker()
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

    private func setupSearchController() {
        let controller = UISearchController(searchResultsController: nil)
        controller.searchBar.placeholder = "Search Items"
        controller.obscuresBackgroundDuringPresentation = false
        self.navigationItem.searchController = controller
        self.navigationItem.hidesSearchBarWhenScrolling = false

        controller.searchBar.rx.text.observeOn(MainScheduler.instance)
                                    .debounce(.milliseconds(150), scheduler: MainScheduler.instance)
                                    .subscribe(onNext: { [weak self] text in
                                        self?.viewModel.process(action: .search(text ?? ""))
                                    })
                                    .disposed(by: self.disposeBag)
    }
}
