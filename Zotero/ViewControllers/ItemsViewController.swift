//
//  ItemsViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 17/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import UIKit
import SwiftUI

import CocoaLumberjack
import RealmSwift
import RxSwift

class ItemsViewController: UIViewController {
    private static let cellId = "ItemCell"
    private static let barButtonItemEmptyTag = 1
    private static let barButtonItemSingleTag = 2

    private let store: ItemsStore
    private let controllers: Controllers
    private let disposeBag: DisposeBag

    private weak var tableView: UITableView!

    private var storeSubscriber: AnyCancellable?
    private var resultsToken: NotificationToken?

    init(store: ItemsStore, controllers: Controllers) {
        self.store = store
        self.controllers = controllers
        self.disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.definesPresentationContext = true

        self.setupTableView()
        self.setupToolbar()
        self.updateNavigationBarItems()
        self.startObservingItemChanges()

        self.storeSubscriber = self.store.$state.receive(on: DispatchQueue.main)
                                                .sink(receiveValue: { [weak self] state in
                                                    self?.updateToolbarItems()
                                                })
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        // Set the search controller here so that it doesn't appear initially
        if self.navigationItem.searchController == nil {
            self.setupSearchController()
        }
    }

    // MARK: - Actions

    private func showNoteEditing(for note: ItemDetailStore.State.Note) {
        self.presentNoteEditor(with: note.text) { [weak self] text in
            var newNote = note
            newNote.title = text.strippedHtml ?? ""
            newNote.text = text
            self?.store.saveChanges(for: newNote)
        }
    }

    private func showNoteCreation() {
        self.presentNoteEditor(with: "", save: self.store.saveNewNote)
    }

    private func presentNoteEditor(with text: String, save: @escaping (String) -> Void) {
        let controller = NoteEditorViewController(text: text, saveAction: save)
        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.isModalInPresentation = true
        self.present(navigationController, animated: true, completion: nil)
    }

    private func showAttachmentPicker() {
        NotificationCenter.default.post(name: .presentFilePicker, object: self.store.addAttachments)
    }

    @objc private func showCollectionPicker() {
        NotificationCenter.default.post(name: .presentCollectionsPicker, object: (self.store.state.library, self.store.assignSelectedItems))
    }

    @objc private func duplicateSelected() {
        let key = self.store.state.selectedItems.first ?? ""
        NotificationCenter.default.post(name: .showDuplicateCreation,
                                        object: (key, self.store.state.library, self.store.state.type.collectionKey))
    }

    private func startEditing() {
        self.tableView.setEditing(true, animated: true)
        self.navigationController?.setToolbarHidden(false, animated: true)
        self.updateNavigationBarItems()
    }

    @objc private func finishEditing() {
        self.tableView.setEditing(false, animated: true)
        self.store.state.selectedItems.removeAll()
        self.navigationController?.setToolbarHidden(true, animated: true)
        self.updateNavigationBarItems()
    }

    private func showItemCreation() {
        let store = ItemDetailStore(type: .creation(libraryId: self.store.state.library.identifier,
                                                    collectionKey: self.store.state.type.collectionKey,
                                                    filesEditable: self.store.state.library.filesEditable),
                                    apiClient: self.controllers.apiClient,
                                    fileStorage: self.controllers.fileStorage,
                                    dbStorage: self.controllers.dbStorage,
                                    schemaController: self.controllers.schemaController)
        self.showItemView(with: store, hidesBackButton: true)
    }

    private func showItemDetail(for item: RItem) {
        switch item.rawType {
        case ItemTypes.note:
            if let note = ItemDetailStore.State.Note(item: item) {
                self.showNoteEditing(for: note)
            }

        default:
            let store = ItemDetailStore(type: .preview(item),
                                        apiClient: self.controllers.apiClient,
                                        fileStorage: self.controllers.fileStorage,
                                        dbStorage: self.controllers.dbStorage,
                                        schemaController: self.controllers.schemaController)
            self.showItemView(with: store)
        }
    }

    private func showItemView(with store: ItemDetailStore, hidesBackButton: Bool = false) {
        let view = ItemDetailView()
                        .environment(\.dbStorage, self.controllers.dbStorage)
                        .environment(\.schemaController, self.controllers.schemaController)
                        .environmentObject(store)
        let controller = UIHostingController(rootView: view)
        if hidesBackButton {
            controller.navigationItem.setHidesBackButton(true, animated: false)
        }
        self.navigationController?.pushViewController(controller, animated: true)
    }

    private func startObservingItemChanges() {
        let startObserving: () -> Void = { [weak self] in
            if let results = self?.store.state.results {
                self?.startObserving(results: results)
            }
        }
        // Set for observation changes
        self.store.state.resultsDidChange = startObserving
        // Start initial observing
        startObserving()
    }

    private func startObserving(results: Results<RItem>) {
        self.resultsToken = results.observe({ [weak self] changes  in
            switch changes {
            case .initial:
                self?.tableView.reloadData()
            case .update(_, let deletions, let insertions, let modifications):
                guard let `self` = self else { return }
                self.tableView.performBatchUpdates({
                    self.tableView.deleteRows(at: deletions.map({ IndexPath(row: $0, section: 0) }), with: .automatic)
                    self.tableView.reloadRows(at: modifications.map({ IndexPath(row: $0, section: 0) }), with: .automatic)
                    self.tableView.insertRows(at: insertions.map({ IndexPath(row: $0, section: 0) }), with: .automatic)
                }, completion: nil)
            case .error(let error):
                DDLogError("ItemsViewController: could not load results - \(error)")
                self?.store.state.error = .dataLoading
            }
        })
    }

    @objc private func showActionSheet() {
        var view = ItemsActionSheetView()
        view.startEditing = { [weak self] in
            self?.startEditing()
        }
        view.dismiss = { [weak self] in
            self?.dismiss(animated: true, completion: nil)
        }
        view.showItemCreation = { [weak self] in
            self?.showItemCreation()
        }
        view.showNoteCreation = { [weak self] in
            self?.showNoteCreation()
        }
        view.showAttachmentPicker = { [weak self] in
            self?.showAttachmentPicker()
        }

        let controller = UIHostingController(rootView: view.environmentObject(self.store))
        controller.view.backgroundColor = .clear
        controller.modalPresentationStyle = .overCurrentContext
        controller.modalTransitionStyle = .crossDissolve
        self.present(controller, animated: true, completion: nil)
    }

    private func updateNavigationBarItems() {
        let trailingitem: UIBarButtonItem

        if self.tableView.isEditing {
            trailingitem = UIBarButtonItem(title: "Done",
                                           style: .done,
                                           target: self,
                                           action: #selector(ItemsViewController.finishEditing))
        } else {
            trailingitem = UIBarButtonItem(image: UIImage(systemName: "ellipsis"),
                                           style: .plain,
                                           target: self,
                                           action: #selector(ItemsViewController.showActionSheet))
        }

        self.navigationItem.rightBarButtonItem = trailingitem
    }

    private func updateToolbarItems() {
        self.toolbarItems?.forEach({ item in
            switch item.tag {
            case ItemsViewController.barButtonItemEmptyTag:
                item.isEnabled = !self.store.state.selectedItems.isEmpty
            case ItemsViewController.barButtonItemSingleTag:
                item.isEnabled = self.store.state.selectedItems.count == 1
            default: break
            }
        })
    }

    // MARK: - Setups

    private func setupTableView() {
        let tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.dragDelegate = self
        tableView.rowHeight = 58
        tableView.allowsMultipleSelectionDuringEditing = true

        self.view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: self.view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor)
        ])

        tableView.register(ItemCell.self, forCellReuseIdentifier: ItemsViewController.cellId)

        self.tableView = tableView
    }

    private func setupToolbar() {
        self.toolbarItems = self.store.state.type.isTrash ? self.createTrashToolbarItems() : self.createNormalToolbarItems()
    }

    private func createNormalToolbarItems() -> [UIBarButtonItem] {
        let pickerItem = UIBarButtonItem(image: UIImage(systemName: "folder.badge.plus"),
                                        style: .plain,
                                        target: self,
                                        action: #selector(ItemsViewController.showCollectionPicker))
        pickerItem.tag = ItemsViewController.barButtonItemEmptyTag

        let trashItem = UIBarButtonItem(image: UIImage(systemName: "trash"),
                                        style: .plain,
                                        target: self.store,
                                        action: #selector(ItemsStore.trashSelectedItems))
        trashItem.tag = ItemsViewController.barButtonItemEmptyTag

        let duplicateItem = UIBarButtonItem(image: UIImage(systemName: "square.on.square"),
                                            style: .plain,
                                            target: self,
                                            action: #selector(ItemsViewController.duplicateSelected))
        duplicateItem.tag = ItemsViewController.barButtonItemSingleTag

        let spacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)

        var items = [spacer, pickerItem, spacer, trashItem, spacer, duplicateItem, spacer]

        if self.store.state.type.collectionKey != nil {
            let removeItem = UIBarButtonItem(image: UIImage(systemName: "folder.badge.minus"),
                                             style: .plain,
                                             target: self.store,
                                             action: #selector(ItemsStore.removeSelectedItemsFromCollection))
            removeItem.tag = ItemsViewController.barButtonItemEmptyTag

            items.insert(contentsOf: [spacer, removeItem], at: 2)
        }

        return items
    }

    private func createTrashToolbarItems() -> [UIBarButtonItem] {
        let spacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let trashItem = UIBarButtonItem(image: UIImage(named: "restore_trash"),
                                        style: .plain,
                                        target: self.store,
                                        action: #selector(ItemsStore.restoreSelectedItems))
        trashItem.tag = ItemsViewController.barButtonItemEmptyTag

        let emptyItem = UIBarButtonItem(image: UIImage(named: "empty_trash"),
                                        style: .plain,
                                        target: self.store,
                                        action: #selector(ItemsStore.deleteSelectedItems))
        emptyItem.tag = ItemsViewController.barButtonItemEmptyTag

        return [spacer, trashItem, spacer, emptyItem, spacer]
    }

    private func setupSearchController() {
        let controller = UISearchController(searchResultsController: nil)
        controller.searchBar.placeholder = "Search Items"
        controller.obscuresBackgroundDuringPresentation = false
        self.navigationItem.searchController = controller


        controller.searchBar.rx.text.observeOn(MainScheduler.instance)
                                    .debounce(.milliseconds(150), scheduler: MainScheduler.instance)
                                    .subscribe(onNext: { [weak self] text in
                                        self?.store.search(for: (text ?? ""))
                                    })
                                    .disposed(by: self.disposeBag)
    }
}

extension ItemsViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.store.state.results?.count ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ItemsViewController.cellId, for: indexPath)

        if let item = self.store.state.results?[indexPath.row],
           let cell = cell as? ItemCell {
            cell.set(item: item)
        }

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let item = self.store.state.results?[indexPath.row] else { return }

        if tableView.isEditing {
            self.store.state.selectedItems.insert(item.key)
        } else {
            tableView.deselectRow(at: indexPath, animated: true)
            self.showItemDetail(for: item)
        }
    }
}

extension ItemsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        if tableView.isEditing,
           let item = self.store.state.results?[indexPath.row] {
            self.store.state.selectedItems.remove(item.key)
        }
    }
}

extension ItemsViewController: UITableViewDragDelegate {
    func tableView(_ tableView: UITableView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        guard let item = self.store.state.results?[indexPath.row] else { return [] }
        let provider = NSItemProvider(object: item.key as NSString)
        return [UIDragItem(itemProvider: provider)]
    }
}
