//
//  ExpandableCollectionsCollectionViewHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 08.02.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class ExpandableCollectionsCollectionViewHandler: NSObject {
    private let collectionsSection: Int = 0
    private unowned let collectionView: UICollectionView
    private unowned let dragDropController: DragDropController
    private unowned let viewModel: ViewModel<CollectionsActionHandler>

    private var dataSource: UICollectionViewDiffableDataSource<Int, Collection>!
    private weak var splitDelegate: SplitControllerDelegate?

    var hasExpandableCollection: Bool {
        let snapshot = self.dataSource.snapshot(for: self.collectionsSection)
        return snapshot.rootItems.count != snapshot.items.count
    }

    var allCollectionsExpanded: Bool {
        let snapshot = self.dataSource.snapshot(for: self.collectionsSection)
        return snapshot.visibleItems.count == snapshot.items.count
    }

    var selectedCollectionIsRoot: Bool {
        return self.dataSource.snapshot(for: self.collectionsSection).rootItems.contains(where: { $0.identifier == self.viewModel.state.selectedCollectionId })
    }

    init(collectionView: UICollectionView, dragDropController: DragDropController, viewModel: ViewModel<CollectionsActionHandler>, splitDelegate: SplitControllerDelegate?) {
        self.collectionView = collectionView
        self.dragDropController = dragDropController
        self.viewModel = viewModel
        self.splitDelegate = splitDelegate

        super.init()

        collectionView.collectionViewLayout = self.createCollectionViewLayout()
        self.collectionView.delegate = self
        self.collectionView.dropDelegate = self
        self.dataSource = self.createDataSource(for: collectionView)
    }

    // MARK: - Scrolling

    func selectIfNeeded(collectionId: CollectionIdentifier, tree: CollectionTree, scrollToPosition: Bool) {
        let selectedIndexPaths = self.collectionView.indexPathsForSelectedItems ?? []

        if selectedIndexPaths.count > 1 {
            // This shouldn't happen, but just in case
            for indexPath in selectedIndexPaths {
                self.collectionView.deselectItem(at: indexPath, animated: false)
            }
        }

        let snapshot = self.dataSource.snapshot(for: self.collectionsSection)

        if !snapshot.items.contains(where: { $0.identifier == collectionId }) {
            // Collection is not stored in this snapshot, nothing to select.
            return
        }

        if !snapshot.visibleItems.contains(where: { $0.identifier == collectionId }) {
            // Selection is collapsed, we need to expand and select it then
            self.update(with: tree, selectedId: collectionId, animated: false) { [weak self] in
                self?.selectIfNeeded(collectionId: collectionId, tree: tree, scrollToPosition: scrollToPosition)
            }
            return
        }

        if let index = self.dataSource.snapshot(for: self.collectionsSection).visibleItems.firstIndex(where: { $0.identifier == collectionId }) {
            let indexPath = IndexPath(item: index, section: 0)
            guard selectedIndexPaths.first != indexPath else { return }
            self.collectionView.selectItem(at: indexPath, animated: false, scrollPosition: scrollToPosition ? .centeredVertically : [])
        } else if let indexPath = selectedIndexPaths.first {
            self.collectionView.deselectItem(at: indexPath, animated: false)
        }
    }

    // MARK: - Data Source

    func update(with tree: CollectionTree, selectedId: CollectionIdentifier, animated: Bool, completion: (() -> Void)? = nil) {
        let newSnapshot = tree.createSnapshot(selectedId: selectedId)

        if self.dataSource.snapshot(for: self.collectionsSection).items.count == newSnapshot.items.count {
            self.dataSource.apply(newSnapshot, to: self.collectionsSection, animatingDifferences: animated, completion: completion)
            return
        }

        // TODO: - iOS bug, applying a section snapshot to section where a new child row is added, parent row doesn't show a collapse button
        // It works fine if a completely new snapshot is applied, which breaks animations though.

        var snapshot = NSDiffableDataSourceSnapshot<Int, Collection>()
        snapshot.appendSections([self.collectionsSection])
        self.dataSource.apply(snapshot, animatingDifferences: animated)
        self.dataSource.apply(newSnapshot, to: self.collectionsSection, animatingDifferences: animated, completion: completion)
    }

    private func createContextMenu(for collection: Collection) -> UIMenu? {
        var actions: [UIAction] = []
        switch collection.identifier {
        case .collection(let key):
            if viewModel.state.library.metadataEditable {
                let edit = UIAction(title: L10n.edit, image: UIImage(systemName: "pencil")) { [weak viewModel] _ in
                    viewModel?.process(action: .startEditing(.edit(collection)))
                }
                let subcollection = UIAction(title: L10n.Collections.newSubcollection, image: UIImage(systemName: "folder.badge.plus")) { [weak viewModel] _ in
                    viewModel?.process(action: .startEditing(.addSubcollection(collection)))
                }
                actions.append(contentsOf: [edit, subcollection])
            }
            
            let createBibliography = UIAction(title: L10n.Collections.createBibliography, image: UIImage(systemName: "doc.on.doc")) { [weak viewModel] _ in
                viewModel?.process(action: .loadItemKeysForBibliography(collection))
            }
            actions.append(createBibliography)

            if viewModel.state.library.metadataEditable {
                let delete = UIAction(title: L10n.delete, image: UIImage(systemName: "trash"), attributes: .destructive) { [weak viewModel] _ in
                    viewModel?.process(action: .deleteCollection(key))
                }
                actions.append(delete)
            }

            if collection.itemCount > 0 {
                actions.insert(contentsOf: [downloadAttachmentsAction(for: collection.identifier, in: viewModel), removeDownloadsAction(for: collection.identifier, in: viewModel)], at: 0)
            }

        case .custom(let type):
            guard collection.itemCount > 0 else { break }
            actions.append(removeDownloadsAction(for: collection.identifier, in: viewModel))

            switch type {
            case .trash:
                if viewModel.state.library.metadataEditable {
                    let trash = UIAction(title: L10n.Collections.emptyTrash, image: UIImage(systemName: "trash"), attributes: .destructive) { [weak viewModel] _ in
                        viewModel?.process(action: .emptyTrash)
                    }
                    actions.append(trash)
                }

            case .publications, .all, .unfiled:
                actions.insert(downloadAttachmentsAction(for: collection.identifier, in: viewModel), at: 0)
            }

        case .search:
            break
        }

        guard !actions.isEmpty else { return nil }
        return UIMenu(children: actions)

        func downloadAttachmentsAction(for identifier: CollectionIdentifier, in viewModel: ViewModel<CollectionsActionHandler>) -> UIAction {
            UIAction(title: L10n.Collections.downloadAttachments, image: UIImage(systemName: "arrow.down.to.line.compact")) { [weak viewModel] _ in
                viewModel?.process(action: .downloadAttachments(identifier))
            }
        }

        func removeDownloadsAction(for identifier: CollectionIdentifier, in viewModel: ViewModel<CollectionsActionHandler>) -> UIAction {
            UIAction(title: L10n.Collections.deleteAttachmentFiles, image: UIImage(systemName: "arrow.down.circle.dotted")) { [weak viewModel] _ in
                viewModel?.process(action: .removeDownloads(identifier))
            }
        }
    }

    private lazy var cellRegistration: UICollectionView.CellRegistration<CollectionCell, Collection> = {
        return UICollectionView.CellRegistration<CollectionCell, Collection> { [weak self] cell, _, collection in
            guard let self = self else { return }

            let snapshot = self.dataSource.snapshot(for: self.collectionsSection)
            let hasChildren = snapshot.contains(collection) && !snapshot.snapshot(of: collection, includingParent: false).items.isEmpty
            var accessories: CollectionCell.Accessories = .chevron

            if !collection.isCollection || Defaults.shared.showCollectionItemCounts {
                accessories.insert(.badge)
            }

            var configuration = CollectionCell.ContentConfiguration(collection: collection, hasChildren: hasChildren, accessories: accessories)
            configuration.isCollapsedProvider = { [weak self] in
                guard let self = self else { return false }
                let snapshot = self.dataSource.snapshot(for: self.collectionsSection)
                return snapshot.contains(collection) ? !snapshot.isExpanded(collection) : false
            }
            configuration.toggleCollapsed = { [weak self, weak cell] in
                guard let self = self, let cell = cell else { return }
                self.viewModel.process(action: .toggleCollapsed(collection))
            }

            cell.contentConfiguration = configuration
            cell.backgroundConfiguration = .listPlainCell()
        }
    }()

    private func createDataSource(for collectionView: UICollectionView) -> UICollectionViewDiffableDataSource<Int, Collection> {
        let registration = self.cellRegistration

        let dataSource = UICollectionViewDiffableDataSource<Int, Collection>(collectionView: collectionView, cellProvider: { collectionView, indexPath, collection in
            return collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: collection)
        })

        var snapshot = NSDiffableDataSourceSnapshot<Int, Collection>()
        snapshot.appendSections([self.collectionsSection])
        dataSource.apply(snapshot, animatingDifferences: false)

        return dataSource
    }

    private func createCollectionViewLayout() -> UICollectionViewCompositionalLayout {
        return UICollectionViewCompositionalLayout { _, environment in
            var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
            configuration.showsSeparators = false
            return NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
        }
    }
}

extension ExpandableCollectionsCollectionViewHandler: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if self.splitDelegate?.isSplit == false {
            collectionView.deselectItem(at: indexPath, animated: true)
        }

        let collection = self.dataSource.snapshot().itemIdentifiers(inSection: indexPath.section)[indexPath.row]

        // We don't need to always show it on iPad, since the currently selected collection is visible. So we show only a new one. On iPhone
        // on the other hand we see only the collection list, so we always need to open the item list for selected collection.
        guard self.splitDelegate?.isSplit == false ? true : collection.identifier != self.viewModel.state.selectedCollectionId else { return }
        self.viewModel.process(action: .select(collection.identifier))
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard let collection = self.dataSource.itemIdentifier(for: indexPath) else { return nil }
        return self.createContextMenu(for: collection).flatMap({ menu in UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: { _ in menu }) })
    }
}

extension ExpandableCollectionsCollectionViewHandler: UICollectionViewDropDelegate {
    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
        guard let indexPath = coordinator.destinationIndexPath,
              let key = self.dataSource.itemIdentifier(for: indexPath)?.identifier.key else { return }

        switch coordinator.proposal.operation {
        case .copy:
            self.dragDropController.keys(from: coordinator.items.map({ $0.dragItem })) { [weak self] keys in
                self?.viewModel.process(action: .assignKeysToCollection(itemKeys: keys, collectionKey: key))
            }
        default: break
        }
    }

    func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
        guard self.viewModel.state.library.metadataEditable &&            // allow only when library is editable
              session.localDragSession != nil &&                          // allow only local drag session
              session.items.compactMap({ $0.localObject as? RItem })      // allow drag from the same library
                           .compactMap({ $0.libraryId }).first == self.viewModel.state.library.identifier else { return UICollectionViewDropProposal(operation: .forbidden) }

        // Allow only dropping to user collections, not custom collections, such as "All Items" or "My Publications"
        if let destination = destinationIndexPath, let collection = self.dataSource.itemIdentifier(for: destination), collection.identifier.isCollection {
            return UICollectionViewDropProposal(operation: .copy, intent: .insertIntoDestinationIndexPath)
        }

        return UICollectionViewDropProposal(operation: .forbidden)
    }
}
