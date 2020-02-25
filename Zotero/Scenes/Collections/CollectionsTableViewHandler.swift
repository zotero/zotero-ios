//
//  CollectionsTableViewHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 25/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RxSwift

class CollectionsTableViewHandler: NSObject {
    private static let cellId = "CollectionRow"
    private unowned let tableView: UITableView
    private unowned let viewModel: ViewModel<CollectionsActionHandler>
    private unowned let dragDropController: DragDropController

    private var dataSource: UITableViewDiffableDataSource<Int, Collection>!

    init(tableView: UITableView, viewModel: ViewModel<CollectionsActionHandler>, dragDropController: DragDropController) {
        self.tableView = tableView
        self.viewModel = viewModel
        self.dragDropController = dragDropController

        super.init()

        self.setupTableView()
        self.setupDataSource()
    }

    // MARK: - Actions

    func update(collections: [Collection], animated: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<Int, Collection>()
        snapshot.appendSections([0])
        snapshot.appendItems(collections, toSection: 0)
        self.dataSource.apply(snapshot, animatingDifferences: animated, completion: nil)
    }

    private func createContextMenu(for collection: Collection) -> UIMenu {
        let edit = UIAction(title: "Edit", image: UIImage(systemName: "pencil")) { [weak self] action in
            self?.viewModel.process(action: .startEditing(.edit(collection)))
        }
        let subcollection = UIAction(title: "New subcollection", image: UIImage(systemName: "folder.badge.plus")) { [weak self] action in
            self?.viewModel.process(action: .startEditing(.addSubcollection(collection)))
        }
        let delete = UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] action in
            self?.viewModel.process(action: .deleteCollection(collection.key))
        }
        return UIMenu(title: "", children: [edit, subcollection, delete])
    }

    // MARK: - Setups

    private func setupTableView() {
        self.tableView.translatesAutoresizingMaskIntoConstraints = false
        self.tableView.delegate = self
        self.tableView.dropDelegate = self
        self.tableView.rowHeight = 44
        self.tableView.register(CollectionCell.self, forCellReuseIdentifier: CollectionsTableViewHandler.cellId)
    }

    private func setupDataSource() {
        self.dataSource = UITableViewDiffableDataSource(tableView: self.tableView,
                                                        cellProvider: { [weak self] (tableView, indexPath, object) -> UITableViewCell? in
            let cell = tableView.dequeueReusableCell(withIdentifier: CollectionsTableViewHandler.cellId, for: indexPath) as? CollectionCell
            cell?.set(collection: object)
            if UIDevice.current.userInterfaceIdiom == .pad && object == self?.viewModel.state.selectedCollection {
                tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
            }
            return cell
        })
    }
}

extension CollectionsTableViewHandler: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if let collection = self.dataSource.itemIdentifier(for: indexPath) {
           let didChange = collection.id != self.viewModel.state.selectedCollection.id
            // We don't need to always show it on iPad, since the currently selected collection is visible. So we show only a new one. On iPhone
            // on the other hand we see only the collection list, so we always need to open the item list for selected collection.
            if UIDevice.current.userInterfaceIdiom == .phone || didChange {
                self.viewModel.process(action: .select(collection))
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

extension CollectionsTableViewHandler: UITableViewDropDelegate {
    func tableView(_ tableView: UITableView, performDropWith coordinator: UITableViewDropCoordinator) {
        guard let indexPath = coordinator.destinationIndexPath else { return }
        let key = self.viewModel.state.collections[indexPath.row].key

        switch coordinator.proposal.operation {
        case .copy:
            self.dragDropController.itemKeys(from: coordinator.items) { [weak self] keys in
                self?.viewModel.process(action: .assignKeysToCollection(keys, key))
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
        if let collection = destinationIndexPath.flatMap({ self.viewModel.state.collections[$0.row] }),
           !collection.type.isCollection {
            return UITableViewDropProposal(operation: .forbidden)
        }

        return UITableViewDropProposal(operation: .copy, intent: .insertIntoDestinationIndexPath)
    }
}
