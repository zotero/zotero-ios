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

class CollectionsViewController: UIViewController {
    private static let cellId = "CollectionRow"

    private let store: CollectionsStore
    private let dbStorage: DbStorage

    private weak var tableView: UITableView!

    private var dataSource: UITableViewDiffableDataSource<Int, Collection>!
    private var storeSubscriber: AnyCancellable?
    private var didAppear: Bool = false

    init(store: CollectionsStore, dbStorage: DbStorage) {
        self.store = store
        self.dbStorage = dbStorage
        super.init(nibName: nil, bundle: nil)
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

        self.updateDataSource(with: self.store.state)

        self.storeSubscriber = self.store.$state.receive(on: DispatchQueue.main)
                                                // Group updates by 1ms, added mainly because of CollectionsStore.replaceCollections where we perform
                                                // deletion and insertion on collections array, which if not debounced creates 2 fast delete/add
                                                // animations and it looks weird to the user, now the update acts as 1 and there is nothing to animate
                                                .debounce(for: .milliseconds(1), scheduler: RunLoop.main)
                                                .sink(receiveValue: { [weak self] state in
                                                    self?.updateDataSource(with: state)
                                                })
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.store.didAppear()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.didAppear = true
    }

    // MARK: - Actions

    private func updateDataSource(with state: CollectionsStore.State) {
        var snapshot = NSDiffableDataSourceSnapshot<Int, Collection>()
        snapshot.appendSections([0])
        snapshot.appendItems(state.collections, toSection: 0)
        self.dataSource.apply(snapshot, animatingDifferences: self.didAppear, completion: nil)
    }

    @objc private func addCollection() {
        self.presentEditView(with: .add)
    }

    private func presentEditView(with type: CollectionsStore.State.EditingType) {
        let view = NavigationView {
            self.createEditView(with: type)
        }
        .navigationViewStyle(StackNavigationViewStyle())

        let controller = UIHostingController(rootView: view)
        controller.isModalInPresentation = true
        self.present(controller, animated: true, completion: nil)
    }

    private func createEditView(with type: CollectionsStore.State.EditingType) -> some View {
        let key: String?
        let name: String
        let parent: Collection?

        switch type {
        case .add:
            key = nil
            name = ""
            parent = nil
        case .addSubcollection(let collection):
            key = nil
            name = ""
            parent = collection
        case .edit(let collection):
            let request = ReadCollectionDbRequest(libraryId: self.store.state.library.identifier, key: collection.key)
            let rCollection = try? self.dbStorage.createCoordinator().perform(request: request)

            key = collection.key
            name = collection.name
            parent = rCollection?.parent.flatMap { Collection(object: $0, level: 0) }
        }

        let store = CollectionEditStore(library: self.store.state.library,
                                           key: key,
                                           name: name,
                                           parent: parent,
                                           dbStorage: self.dbStorage)
        store.shouldDismiss = { [weak self] in
            self?.dismiss(animated: true, completion: nil)
        }

        return CollectionEditView(closeAction: { [weak self] in self?.dismiss(animated: true, completion: nil) })
                    .environment(\.dbStorage, self.dbStorage)
                    .environmentObject(store)
    }

    private func createContextMenu(for collection: Collection) -> UIMenu {
        let edit = UIAction(title: "Edit", image: UIImage(systemName: "pencil")) { action in
            self.presentEditView(with: .edit(collection))
        }
        let subcollection = UIAction(title: "New subcollection", image: UIImage(systemName: "folder.badge.plus")) { action in
            self.presentEditView(with: .addSubcollection(collection))
        }
        let delete = UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { action in
            self.store.deleteCollection(with: collection.key)
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
            if object == self?.store.state.selectedCollection {
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
}

extension CollectionsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if let collection = self.dataSource.itemIdentifier(for: indexPath) {
            self.store.state.selectedCollection = collection
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
        let collection = self.store.state.collections[indexPath.row]

        switch coordinator.proposal.operation {
        case .copy:
            self.loadKeys(from: coordinator.items) { [weak self] keys in
                self?.store.assignItems(keys: keys, to: collection.key)
            }
        default: break
        }
    }

    func tableView(_ tableView: UITableView,
                   dropSessionDidUpdate session: UIDropSession,
                   withDestinationIndexPath destinationIndexPath: IndexPath?) -> UITableViewDropProposal {
        guard session.localDragSession != nil,
              let indexPath = destinationIndexPath else { return UITableViewDropProposal(operation: .forbidden) }
        let collection = self.store.state.collections[indexPath.row]
        guard collection.type.isCollection else { return UITableViewDropProposal(operation: .forbidden) }
        return UITableViewDropProposal(operation: .copy, intent: .insertIntoDestinationIndexPath)
    }

    private func loadKeys(from items: [UITableViewDropItem], completed: @escaping ([String]) -> Void) {
        var keys: [String] = []

        let group = DispatchGroup()

        items.forEach { item in
            group.enter()
            item.dragItem.itemProvider.loadObject(ofClass: NSString.self) { nsString, error in
                if let key = nsString as? String {
                    keys.append(key)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completed(keys)
        }
    }
}

struct CollectionsVewControllerRepresentable: UIViewControllerRepresentable {
    let store: CollectionsStore
    let dbStorage: DbStorage

    func makeUIViewController(context: Context) -> CollectionsViewController {
        return CollectionsViewController(store: self.store, dbStorage: self.dbStorage)
    }

    func updateUIViewController(_ uiViewController: CollectionsViewController, context: Context) {
    }
}
