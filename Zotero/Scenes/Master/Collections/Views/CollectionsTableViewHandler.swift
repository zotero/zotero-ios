//
//  CollectionsTableViewHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 25/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import Differ
import RxSwift

final class CollectionsTableViewHandler: NSObject {
    private static let cellId = "CollectionRow"
    private unowned let tableView: UITableView
    private unowned let viewModel: ViewModel<CollectionsActionHandler>
    private unowned let dragDropController: DragDropController
    private let disposeBag: DisposeBag

    private var snapshot: [Collection] = []
    private weak var splitDelegate: SplitControllerDelegate?

    init(tableView: UITableView, viewModel: ViewModel<CollectionsActionHandler>,
         dragDropController: DragDropController, splitDelegate: SplitControllerDelegate?) {
        self.tableView = tableView
        self.viewModel = viewModel
        self.dragDropController = dragDropController
        self.splitDelegate = splitDelegate
        self.disposeBag = DisposeBag()

        super.init()

        self.setupTableView()
        self.setupKeyboardObserving()
    }

    // MARK: - Actions

    func selectIfNeeded(collection: Collection) {
        if let index = self.snapshot.firstIndex(where: { $0.id == collection.id }) {
            guard self.tableView.indexPathForSelectedRow?.row != index else { return }
            self.tableView.selectRow(at: IndexPath(row: index, section: 0), animated: false, scrollPosition: .none)
        } else if let indexPath = self.tableView.indexPathForSelectedRow {
            self.tableView.deselectRow(at: indexPath, animated: false)
        }
    }

    func updateAllItemCell(with collection: Collection) {
        self.snapshot[0] = collection
        guard let cell = self.tableView.cellForRow(at: IndexPath(row: 0, section: 0)) as? CollectionCell else { return }
        cell.updateRightViews(for: collection)
    }

    func updateTrashItemCell(with collection: Collection) {
        let row = self.snapshot.count - 1
        self.snapshot[row] = collection
        guard let cell = self.tableView.cellForRow(at: IndexPath(row: row, section: 0)) as? CollectionCell else { return }
        cell.updateRightViews(for: collection)
    }

    func update(collections: [Collection], animated: Bool, completed: (() -> Void)? = nil) {
        if !animated {
            // If animation is not needed, just update snapshot and reload tableView
            self.snapshot = collections
            self.tableView.reloadData()
            completed?()
            return
        }

        let diff = self.snapshot.extendedDiff(collections)
        let (insertions, deletions, reloads, moves) = self.updates(from: diff)

        if insertions.isEmpty && deletions.isEmpty && moves.isEmpty && !reloads.isEmpty {
            // If there are only reloads, reload only visible cells by hand.
            self.updateOnlyVisibleCells(for: reloads, collections: collections)
            completed?()
            return
        }

        // If there are other actions as well, perform all actions
        self.performBatchUpdates(collections: collections, insertions: insertions, deletions: deletions,
                                 reloads: reloads, moves: moves, completed: completed)
    }

    private func performBatchUpdates(collections: [Collection], insertions: [IndexPath], deletions: [IndexPath], reloads: [IndexPath], moves: [(IndexPath, IndexPath)], completed: (() -> Void)?) {
        self.tableView.performBatchUpdates {
            self.snapshot = collections

            self.tableView.deleteRows(at: deletions, with: .fade)
            self.tableView.insertRows(at: insertions, with: .fade)
            self.tableView.reloadRows(at: reloads, with: .automatic)
            moves.forEach { self.tableView.moveRow(at: $0.0, to: $0.1) }
        } completion: { _ in
            completed?()
        }
    }

    private func updateOnlyVisibleCells(for indexPaths: [IndexPath], collections: [Collection]) {
        self.snapshot = collections
        
        guard let visibleIndexPaths = self.tableView.indexPathsForVisibleRows else { return }
        for indexPath in visibleIndexPaths.filter({ indexPaths.contains($0) }) {
            guard let cell = self.tableView.cellForRow(at: indexPath) as? CollectionCell else { continue }
            let collection = collections[indexPath.row]
            cell.set(collection: collection, toggleCollapsed: { [weak self] in
                self?.viewModel.process(action: .toggleCollapsed(collection))
            })
        }
    }

    private func updates(from diff: ExtendedDiff) -> (insertions: [IndexPath], deletions: [IndexPath], reloads: [IndexPath], moves: [(IndexPath, IndexPath)]) {
        var insertions: Set<Int> = []
        var deletions: Set<Int> = []
        var moves: [(Int, Int)] = []

        diff.elements.forEach { element in
            switch element {
            case .delete(let index):
                deletions.insert(index)
            case .insert(let index):
                insertions.insert(index)
            case .move(let from, let to):
                moves.append((from, to))
            }
        }

        let reloads = insertions.intersection(deletions)
        insertions.subtract(reloads)
        deletions.subtract(reloads)

        return (insertions.map({ IndexPath(row: $0, section: 0) }),
                deletions.map({ IndexPath(row: $0, section: 0) }),
                reloads.map({ IndexPath(row: $0, section: 0) }),
                moves.map({ (IndexPath(row: $0.0, section: 0), IndexPath(row: $0.1, section: 0)) }))
    }

    private func createContextMenu(for collection: Collection) -> UIMenu {
        let edit = UIAction(title: L10n.edit, image: UIImage(systemName: "pencil")) { [weak self] action in
            self?.viewModel.process(action: .startEditing(.edit(collection)))
        }
        let subcollection = UIAction(title: L10n.Collections.newSubcollection, image: UIImage(systemName: "folder.badge.plus")) { [weak self] action in
            self?.viewModel.process(action: .startEditing(.addSubcollection(collection)))
        }
        let delete = UIAction(title: L10n.delete, image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] action in
            self?.viewModel.process(action: .deleteCollection(collection.key))
        }
        return UIMenu(title: "", children: [edit, subcollection, delete])
    }

    // MARK: - Setups

    private func setupTableView() {
        self.tableView.translatesAutoresizingMaskIntoConstraints = false
        self.tableView.delegate = self
        self.tableView.dataSource = self
        self.tableView.dropDelegate = self
        self.tableView.rowHeight = 44
        self.tableView.register(UINib(nibName: "CollectionCell", bundle: nil), forCellReuseIdentifier: CollectionsTableViewHandler.cellId)
        self.tableView.tableFooterView = UIView()
    }

    private func setupTableView(with keyboardData: KeyboardData) {
        var insets = self.tableView.contentInset
        insets.bottom = keyboardData.endFrame.height
        self.tableView.contentInset = insets
    }

    private func setupKeyboardObserving() {
        NotificationCenter.default
                          .keyboardWillShow
                          .observeOn(MainScheduler.instance)
                          .subscribe(onNext: { [weak self] notification in
                              if let data = notification.keyboardData {
                                  self?.setupTableView(with: data)
                              }
                          })
                          .disposed(by: self.disposeBag)

        NotificationCenter.default
                          .keyboardWillHide
                          .observeOn(MainScheduler.instance)
                          .subscribe(onNext: { [weak self] notification in
                              if let data = notification.keyboardData {
                                  self?.setupTableView(with: data)
                              }
                          })
                          .disposed(by: self.disposeBag)
    }
}

extension CollectionsTableViewHandler: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.snapshot.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: CollectionsTableViewHandler.cellId, for: indexPath)
        if let cell = cell as? CollectionCell {
            let collection = self.snapshot[indexPath.row]
            cell.set(collection: collection, toggleCollapsed: { [weak self] in
                self?.viewModel.process(action: .toggleCollapsed(collection))
            })
        }
        return cell
    }
}

extension CollectionsTableViewHandler: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if self.splitDelegate?.isSplit == false {
            tableView.deselectRow(at: indexPath, animated: true)
        }

        // We don't need to always show it on iPad, since the currently selected collection is visible. So we show only a new one. On iPhone
        // on the other hand we see only the collection list, so we always need to open the item list for selected collection.
        let collection = self.snapshot[indexPath.row]
        guard self.splitDelegate?.isSplit == false ? true : collection.id != self.viewModel.state.selectedCollection.id else { return }
        self.viewModel.process(action: .select(collection))
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        if !self.viewModel.state.library.metadataEditable {
            return nil
        }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ -> UIMenu? in
            guard let collection = self?.snapshot[indexPath.row], collection.type.isCollection else { return nil }
            return self?.createContextMenu(for: collection)
        }
    }
}

extension CollectionsTableViewHandler: UITableViewDropDelegate {
    func tableView(_ tableView: UITableView, performDropWith coordinator: UITableViewDropCoordinator) {
        guard let indexPath = coordinator.destinationIndexPath else { return }
        let key = self.snapshot[indexPath.row].key

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
        if !self.viewModel.state.library.metadataEditable {
            return UITableViewDropProposal(operation: .forbidden)
        }
        // Allow only local drag session
        guard session.localDragSession != nil else { return UITableViewDropProposal(operation: .forbidden) }

        // Allow only dropping to user collections, not custom collections, such as "All Items" or "My Publications"
        if let collection = destinationIndexPath.flatMap({ self.snapshot[$0.row] }),
           !collection.type.isCollection {
            return UITableViewDropProposal(operation: .forbidden)
        }

        return UITableViewDropProposal(operation: .copy, intent: .insertIntoDestinationIndexPath)
    }
}
