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

class ItemsViewController: UIViewController {
    private static let cellId = "ItemCell"

    private let store: ItemsStore
    private let controllers: Controllers

    private weak var tableView: UITableView!
    private weak var duplicateItem: UIBarButtonItem!

    private var storeSubscriber: AnyCancellable?
    private var resultsToken: NotificationToken?

    init(store: ItemsStore, controllers: Controllers) {
        self.store = store
        self.controllers = controllers
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupTableView()
        self.setupToolbar()
        self.updateNavigationBarItems()

        self.store.state.resultsDidChange = { [weak self] in
            if let results = self?.store.state.results {
                self?.startObserving(results: results)
            }
        }
        self.storeSubscriber = self.store.$state.receive(on: DispatchQueue.main)
                                                .sink(receiveValue: { [weak self] state in
                                                    self?.duplicateItem.isEnabled = state.selectedItems.count == 1
                                                })
    }

    // MARK: - Actions

    @objc private func showCollectionPicker() {
        NotificationCenter.default.post(name: .presentCollectionsPicker, object: (self.store.state.library, self.store.assignSelectedItems))
    }

    @objc private func trashSelected() {
        self.store.trashSelectedItems()
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
        let view = ItemDetailView().environmentObject(store)

        let controller = UIHostingController(rootView: view)
        controller.navigationItem.setHidesBackButton(true, animated: false)
        self.navigationController?.pushViewController(controller, animated: true)
    }

    private func showItemDetail(for item: RItem) {
        let store = ItemDetailStore(type: .preview(item),
                                    apiClient: self.controllers.apiClient,
                                    fileStorage: self.controllers.fileStorage,
                                    dbStorage: self.controllers.dbStorage,
                                    schemaController: self.controllers.schemaController)
        let view = ItemDetailView().environmentObject(store)

        let controller = UIHostingController(rootView: view)
        self.navigationController?.pushViewController(controller, animated: true)
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

    // MARK: - Setups

    private func setupTableView() {
        let tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
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
        let pickerItem = UIBarButtonItem(image: UIImage(systemName: "folder.badge.plus"),
                                         style: .plain,
                                         target: self,
                                         action: #selector(ItemsViewController.showCollectionPicker))
         let trashItem = UIBarButtonItem(image: UIImage(systemName: "trash"),
                                         style: .plain,
                                         target: self,
                                         action: #selector(ItemsViewController.trashSelected))
         let duplicateItem = UIBarButtonItem(image: UIImage(systemName: "square.on.square"),
                                             style: .plain,
                                             target: self,
                                             action: #selector(ItemsViewController.duplicateSelected))
        let spacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)

        self.toolbarItems = [spacer, pickerItem, spacer, trashItem, spacer, duplicateItem, spacer]
        self.duplicateItem = duplicateItem
    }
}

extension ItemsViewController: UITableViewDelegate, UITableViewDataSource {
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

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        if tableView.isEditing,
           let item = self.store.state.results?[indexPath.row] {
            self.store.state.selectedItems.remove(item.key)
        }
    }
}
