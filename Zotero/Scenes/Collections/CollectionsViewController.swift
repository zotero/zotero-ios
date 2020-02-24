//
//  CollectionsViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 17/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import UIKit
import SwiftUI

import RealmSwift
import RxSwift

class CollectionsViewController: UIViewController {
    private static let cellId = "CollectionRow"

    private let store: ViewModel<CollectionsActionHandler>
    private unowned let dragDropController: DragDropController
    private unowned let dbStorage: DbStorage
    private let disposeBag: DisposeBag

    private weak var tableView: UITableView!

    private var dataSource: UITableViewDiffableDataSource<Int, Collection>!
    private var didAppear: Bool

    private var collectionsToken: NotificationToken?
    private var searchesToken: NotificationToken?

    init(results: CollectionsResults?, viewModel: ViewModel<CollectionsActionHandler>, dbStorage: DbStorage, dragDropController: DragDropController) {
        self.store = viewModel
        self.dbStorage = dbStorage
        self.dragDropController = dragDropController
        self.disposeBag = DisposeBag()
        self.didAppear = false

        super.init(nibName: nil, bundle: nil)

        if let results = results {
            self.setupObserving(for: results)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationItem.title = self.store.state.library.name
        self.setupNavbarItems()

        self.setupTableView()
        self.setupDataSource()

        self.updateDataSource(with: self.store.state.collections)

        self.store.stateObservable
                  .observeOn(MainScheduler.instance)
                  .subscribe(onNext: { [weak self] state in
                      self?.update(to: state)
                  })
                  .disposed(by: self.disposeBag)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if UIDevice.current.userInterfaceIdiom == .pad {
            self.show(selectedCollection: self.store.state.selectedCollection, library: self.store.state.library)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.didAppear = true
    }

    // MARK: - UI state

    private func update(to state: CollectionsState) {
        if state.changes.contains(.results) {
            self.updateDataSource(with: state.collections)
        }
        if state.changes.contains(.selection) {
            self.show(selectedCollection: state.selectedCollection, library: state.library)
        }
        if let data = state.editingData {
            self.presentEditView(for: data)
        }
    }

    private func updateDataSource(with collections: [Collection]) {
        var snapshot = NSDiffableDataSourceSnapshot<Int, Collection>()
        snapshot.appendSections([0])
        snapshot.appendItems(collections, toSection: 0)
        self.dataSource.apply(snapshot, animatingDifferences: self.didAppear, completion: nil)
    }

    // MARK: - Navigation

    private func show(selectedCollection: Collection, library: Library) {
        NotificationCenter.default.post(name: .splitViewDetailChanged, object: (selectedCollection, library))
    }

    @objc private func addCollection() {
        self.store.process(action: .startEditing(.add))
    }

    private func presentEditView(for data: CollectionStateEditingData) {
        let view = NavigationView {
            self.createEditView(for: data)
        }
        .navigationViewStyle(StackNavigationViewStyle())

        let controller = UIHostingController(rootView: view)
        controller.isModalInPresentation = true
        self.present(controller, animated: true, completion: nil)
    }

    private func createEditView(for data: CollectionStateEditingData) -> some View {
        let store = CollectionEditStore(library: self.store.state.library, key: data.0, name: data.1,
                                        parent: data.2, dbStorage: self.dbStorage)
        store.shouldDismiss = { [weak self] in
            self?.dismiss(animated: true, completion: nil)
        }

        return CollectionEditView(closeAction: { [weak self] in self?.dismiss(animated: true, completion: nil) })
                    .environment(\.dbStorage, self.dbStorage)
                    .environmentObject(store)
    }

    private func createContextMenu(for collection: Collection) -> UIMenu {
        let edit = UIAction(title: "Edit", image: UIImage(systemName: "pencil")) { [weak self] action in
            self?.store.process(action: .startEditing(.edit(collection)))
        }
        let subcollection = UIAction(title: "New subcollection", image: UIImage(systemName: "folder.badge.plus")) { [weak self] action in
            self?.store.process(action: .startEditing(.addSubcollection(collection)))
        }
        let delete = UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] action in
            self?.store.process(action: .deleteCollection(collection.key))
        }
        return UIMenu(title: "", children: [edit, subcollection, delete])
    }

    // MARK: - Setups

    private func setupTableView() {
        let tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dropDelegate = self
        tableView.rowHeight = 44

        self.view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: self.view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor)
        ])

        tableView.register(CollectionCell.self, forCellReuseIdentifier: CollectionsViewController.cellId)

        self.tableView = tableView
    }

    private func setupDataSource() {
        self.dataSource = UITableViewDiffableDataSource(tableView: self.tableView,
                                                        cellProvider: { [weak self] (tableView, indexPath, object) -> UITableViewCell? in
            let cell = tableView.dequeueReusableCell(withIdentifier: CollectionsViewController.cellId, for: indexPath) as? CollectionCell
            cell?.set(collection: object)
            if UIDevice.current.userInterfaceIdiom == .pad && object == self?.store.state.selectedCollection {
                tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
            }
            return cell
        })
    }

    private func setupNavbarItems() {
        let item = UIBarButtonItem(image: UIImage(systemName: "plus"),
                                   style: .plain,
                                   target: self,
                                   action: #selector(CollectionsViewController.addCollection))
        self.navigationItem.rightBarButtonItem = item
    }

    private func setupObserving(for results: CollectionsResults) {
        self.collectionsToken = results.1.observe({ [weak self] changes in
            guard let `self` = self else { return }
            switch changes {
            case .update(let objects, _, _, _):
                self.store.process(action: .updateCollections(CollectionTreeBuilder.collections(from: objects)))
            case .initial: break
            case .error: break
            }
        })
        self.searchesToken = results.2.observe({ [weak self] changes in
            guard let `self` = self else { return }
            switch changes {
            case .update(let objects, _, _, _):
                self.store.process(action: .updateCollections(CollectionTreeBuilder.collections(from: objects)))
            case .initial: break
            case .error: break
            }
        })
    }
}

extension CollectionsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if let collection = self.dataSource.itemIdentifier(for: indexPath) {
            let didChange = collection.id != self.store.state.selectedCollection.id
            // We don't need to always show it on iPad, since the currently selected collection is visible. So we show only a new one. On iPhone
            // on the other hand we see only the collection list, so we always need to open the item list for selected collection.
            if UIDevice.current.userInterfaceIdiom == .phone || didChange {
                self.store.process(action: .select(collection))
            }
        }

        if UIDevice.current.userInterfaceIdiom != .pad {
            tableView.deselectRow(at: indexPath, animated: true)
        }
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ -> UIMenu? in
            guard let collection = self?.dataSource.itemIdentifier(for: indexPath) else { return nil }
            return self?.createContextMenu(for: collection)
        }
    }
}

extension CollectionsViewController: UITableViewDropDelegate {
    func tableView(_ tableView: UITableView, performDropWith coordinator: UITableViewDropCoordinator) {
        guard let indexPath = coordinator.destinationIndexPath else { return }
        let key = self.store.state.collections[indexPath.row].key

        switch coordinator.proposal.operation {
        case .copy:
            self.dragDropController.itemKeys(from: coordinator.items) { [weak self] keys in
                self?.store.process(action: .assignKeysToCollection(keys, key))
            }
        default: break
        }
    }

    func tableView(_ tableView: UITableView,
                   dropSessionDidUpdate session: UIDropSession,
                   withDestinationIndexPath destinationIndexPath: IndexPath?) -> UITableViewDropProposal {
        // Allow only local drag session
        guard session.localDragSession != nil else { return UITableViewDropProposal(operation: .forbidden) }

        // Allow only dropping to user collections, not custom collections, such as "All Items" or "My Publications"
        if let collection = destinationIndexPath.flatMap({ self.store.state.collections[$0.row] }),
           !collection.type.isCollection {
            return UITableViewDropProposal(operation: .forbidden)
        }

        return UITableViewDropProposal(operation: .copy, intent: .insertIntoDestinationIndexPath)
    }
}
