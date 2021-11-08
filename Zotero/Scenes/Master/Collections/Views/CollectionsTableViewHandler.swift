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

    private var dataSource: DiffableDataSource<Int, Collection>!
//    private var snapshot: [Collection] = []
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

    func selectIfNeeded(collectionId: CollectionIdentifier) {
        if let indexPath = self.dataSource.snapshot.indexPath(where: { $0.identifier == collectionId }) {
            guard self.tableView.indexPathForSelectedRow != indexPath else { return }
            self.tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
        } else if let indexPath = self.tableView.indexPathForSelectedRow {
            self.tableView.deselectRow(at: indexPath, animated: false)
        }
    }

    func updateAllItemCell() {
        guard let collection = self.viewModel.state.collections.first else { return }
        self.dataSource.update(object: collection, at: IndexPath(row: 0, section: 0))
    }

    func updateTrashItemCell() {
        guard let collection = self.viewModel.state.collections.last else { return }
        let count = self.dataSource.snapshot.count(for: 0)
        guard count > 0 else { return }
        self.dataSource.update(object: collection, at: IndexPath(row: count - 1, section: 0))
    }

    func updateCollections(animated: Bool, completed: (() -> Void)? = nil) {
        var snapshot = DiffableDataSourceSnapshot<Int, Collection>(isEditing: false)
        snapshot.append(section: 0)
        snapshot.append(objects: self.viewModel.state.collections.filter({ $0.visible }), for: 0)
        let animation: DiffableDataSourceAnimation = !animated ? .none : .rows(reload: .automatic, insert: .bottom, delete: .bottom)
        self.dataSource.apply(snapshot: snapshot, animation: animation, completion: { finished in
            guard finished else { return }
            completed?()
        })
//        if !animated {
//            // If animation is not needed, just update snapshot and reload tableView
//            self.snapshot = collections
//            self.tableView.reloadData()
//            completed?()
//            return
//        }
//
//        let diff = self.snapshot.extendedDiff(collections)
//        let (insertions, deletions, reloads, moves) = self.updates(from: diff)
//
//        if insertions.isEmpty && deletions.isEmpty && moves.isEmpty && !reloads.isEmpty {
//            // If there are only reloads, reload only visible cells by hand.
//            self.updateOnlyVisibleCells(for: reloads, collections: collections)
//            completed?()
//            return
//        }
//
//        // If there are other actions as well, perform all actions
//        self.performBatchUpdates(collections: collections, insertions: insertions, deletions: deletions, reloads: reloads, moves: moves, completed: completed)
    }
//
//    private func performBatchUpdates(collections: [Collection], insertions: [IndexPath], deletions: [IndexPath], reloads: [IndexPath], moves: [(IndexPath, IndexPath)], completed: (() -> Void)?) {
//        self.tableView.performBatchUpdates {
//            self.snapshot = collections
//
//            self.tableView.deleteRows(at: deletions, with: .bottom)
//            self.tableView.insertRows(at: insertions, with: .bottom)
//            self.tableView.reloadRows(at: reloads, with: .automatic)
//            moves.forEach { self.tableView.moveRow(at: $0.0, to: $0.1) }
//        } completion: { _ in
//            completed?()
//        }
//    }
//
//    private func updateOnlyVisibleCells(for indexPaths: [IndexPath], collections: [Collection]) {
//        self.snapshot = collections
//
//        guard let visibleIndexPaths = self.tableView.indexPathsForVisibleRows else { return }
//        for indexPath in visibleIndexPaths.filter({ indexPaths.contains($0) }) {
//            guard let cell = self.tableView.cellForRow(at: indexPath) as? CollectionCell else { continue }
//            let collection = collections[indexPath.row]
//            cell.set(collection: collection, toggleCollapsed: { [weak self] in
//                self?.viewModel.process(action: .toggleCollapsed(collection))
//            })
//        }
//    }
//
//    private func updates(from diff: ExtendedDiff) -> (insertions: [IndexPath], deletions: [IndexPath], reloads: [IndexPath], moves: [(IndexPath, IndexPath)]) {
//        var insertions: Set<Int> = []
//        var deletions: Set<Int> = []
//        var moves: [(Int, Int)] = []
//
//        diff.elements.forEach { element in
//            switch element {
//            case .delete(let index):
//                deletions.insert(index)
//            case .insert(let index):
//                insertions.insert(index)
//            case .move(let from, let to):
//                moves.append((from, to))
//            }
//        }
//
//        let reloads = insertions.intersection(deletions)
//        insertions.subtract(reloads)
//        deletions.subtract(reloads)
//
//        return (insertions.map({ IndexPath(row: $0, section: 0) }),
//                deletions.map({ IndexPath(row: $0, section: 0) }),
//                reloads.map({ IndexPath(row: $0, section: 0) }),
//                moves.map({ (IndexPath(row: $0.0, section: 0), IndexPath(row: $0.1, section: 0)) }))
//    }

    private func createContextMenu(for collection: Collection) -> UIMenu? {
        switch collection.identifier {
        case .collection(let key):
            guard self.viewModel.state.library.metadataEditable else { return nil }
            let edit = UIAction(title: L10n.edit, image: UIImage(systemName: "pencil")) { [weak self] _ in
                self?.viewModel.process(action: .startEditing(.edit(collection)))
            }
            let subcollection = UIAction(title: L10n.Collections.newSubcollection, image: UIImage(systemName: "folder.badge.plus")) { [weak self] _ in
                self?.viewModel.process(action: .startEditing(.addSubcollection(collection)))
            }
            let createBibliography = UIAction(title: L10n.Collections.createBibliography, image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
                self?.viewModel.process(action: .loadItemKeysForBibliography(collection))
            }
            let delete = UIAction(title: L10n.delete, image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                self?.viewModel.process(action: .deleteCollection(key))
            }
            return UIMenu(title: "", children: [edit, subcollection, createBibliography, delete])

        case .custom(let type):
            switch type {
            case .trash:
                guard self.viewModel.state.library.metadataEditable && collection.itemCount > 0 else { return nil }
                let trash = UIAction(title: L10n.Collections.emptyTrash, image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                    self?.viewModel.process(action: .emptyTrash)
                }
                return UIMenu(title: "", children: [trash])

            case .publications, .all:
                return nil
            }

        case .search:
            return nil
        }
    }

    // MARK: - Setups

    private func setupTableView() {
        self.tableView.translatesAutoresizingMaskIntoConstraints = false
        self.tableView.delegate = self
//        self.tableView.dataSource = self
        self.tableView.dropDelegate = self
        self.tableView.rowHeight = 44
        self.tableView.register(UINib(nibName: "CollectionCell", bundle: nil), forCellReuseIdentifier: CollectionsTableViewHandler.cellId)
        self.tableView.tableFooterView = UIView()

        self.dataSource = DiffableDataSource(tableView: self.tableView,
                                             dequeueAction: { tableView, indexPath, _, _ in
                                                return tableView.dequeueReusableCell(withIdentifier: CollectionsTableViewHandler.cellId, for: indexPath)
                                             }, setupAction: { [weak self] cell, _, _, collection in
                                                 guard let cell = cell as? CollectionCell else { return }
                                                 cell.set(collection: collection, toggleCollapsed: {
                                                     self?.viewModel.process(action: .toggleCollapsed(collection))
                                                 })
                                             })
    }

    private func setupTableView(with keyboardData: KeyboardData) {
        var insets = self.tableView.contentInset
        insets.bottom = keyboardData.endFrame.height
        self.tableView.contentInset = insets
    }

    private func setupKeyboardObserving() {
        NotificationCenter.default
                          .keyboardWillShow
                          .observe(on: MainScheduler.instance)
                          .subscribe(onNext: { [weak self] notification in
                              if let data = notification.keyboardData {
                                  self?.setupTableView(with: data)
                              }
                          })
                          .disposed(by: self.disposeBag)

        NotificationCenter.default
                          .keyboardWillHide
                          .observe(on: MainScheduler.instance)
                          .subscribe(onNext: { [weak self] notification in
                              if let data = notification.keyboardData {
                                  self?.setupTableView(with: data)
                              }
                          })
                          .disposed(by: self.disposeBag)
    }
}

//extension CollectionsTableViewHandler: UITableViewDataSource {
//    func numberOfSections(in tableView: UITableView) -> Int {
//        return 1
//    }
//
//    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
//        return self.snapshot.count
//    }
//
//    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
//        let cell = tableView.dequeueReusableCell(withIdentifier: CollectionsTableViewHandler.cellId, for: indexPath)
//        if let cell = cell as? CollectionCell {
//            let collection = self.snapshot[indexPath.row]
//            cell.set(collection: collection, toggleCollapsed: { [weak self] in
//                self?.viewModel.process(action: .toggleCollapsed(collection))
//            })
//        }
//        return cell
//    }
//}

extension CollectionsTableViewHandler: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if self.splitDelegate?.isSplit == false {
            tableView.deselectRow(at: indexPath, animated: true)
        }

        // We don't need to always show it on iPad, since the currently selected collection is visible. So we show only a new one. On iPhone
        // on the other hand we see only the collection list, so we always need to open the item list for selected collection.
        guard let collection = self.dataSource.snapshot.object(at: indexPath),
              self.splitDelegate?.isSplit == false ? true : collection.identifier != self.viewModel.state.selectedCollectionId else { return }
        self.viewModel.process(action: .select(collection.identifier))
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard let collection = self.dataSource.snapshot.object(at: indexPath) else { return nil }
        return self.createContextMenu(for: collection).flatMap({ menu in UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: { _ in menu }) })
    }
}

extension CollectionsTableViewHandler: UITableViewDropDelegate {
    func tableView(_ tableView: UITableView, performDropWith coordinator: UITableViewDropCoordinator) {
        guard let indexPath = coordinator.destinationIndexPath,
              let key = self.dataSource.snapshot.object(at: indexPath)?.identifier.key else { return }

        switch coordinator.proposal.operation {
        case .copy:
            self.dragDropController.itemKeys(from: coordinator.items) { [weak self] keys in
                self?.viewModel.process(action: .assignKeysToCollection(keys, key))
            }
        default: break
        }
    }

    func tableView(_ tableView: UITableView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UITableViewDropProposal {
        if !self.viewModel.state.library.metadataEditable {
            return UITableViewDropProposal(operation: .forbidden)
        }
        // Allow only local drag session
        guard session.localDragSession != nil else { return UITableViewDropProposal(operation: .forbidden) }

        // Allow only dropping to user collections, not custom collections, such as "All Items" or "My Publications"
        if let destination = destinationIndexPath, let collection = self.dataSource.snapshot.object(at: destination), collection.identifier.isCollection {
            return UITableViewDropProposal(operation: .copy, intent: .insertIntoDestinationIndexPath)
        }

        return UITableViewDropProposal(operation: .forbidden)
    }
}
