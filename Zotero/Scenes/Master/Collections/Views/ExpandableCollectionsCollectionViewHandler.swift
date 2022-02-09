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
        self.dataSource = self.createDataSource(for: collectionView)
    }

    // MARK: - Scrolling

    func selectIfNeeded(collectionId: CollectionIdentifier, scrollToPosition: Bool) {
        let selectedIndexPaths = self.collectionView.indexPathsForSelectedItems ?? []

        if selectedIndexPaths.count > 1 {
            // This shouldn't happen, but just in case
            for indexPath in selectedIndexPaths {
                self.collectionView.deselectItem(at: indexPath, animated: false)
            }
        }

        if let index = self.dataSource.snapshot(for: self.collectionsSection).visibleItems.firstIndex(where: { $0.identifier == collectionId }) {
            let indexPath = IndexPath(item: index, section: 0)
            guard selectedIndexPaths.first != indexPath else { return }
            self.collectionView.selectItem(at: indexPath, animated: false, scrollPosition: scrollToPosition ? .centeredVertically : [])
        } else if let indexPath = selectedIndexPaths.first {
            self.collectionView.deselectItem(at: indexPath, animated: false)
        }
    }

    // MARK: - Expandability Controls
    func update(collapsedState: [CollectionIdentifier: Bool]) {
        var snapshot = self.dataSource.snapshot(for: self.collectionsSection)
        let (collapsed, expanded) = self.separateExpandedFromCollapsed(collections: snapshot.items, collapsedState: collapsedState)
        snapshot.collapse(collapsed)
        snapshot.expand(expanded)
        self.dataSource.apply(snapshot, to: 0)
    }

    // MARK: - Data Source

    func update(root: [CollectionIdentifier], children: [CollectionIdentifier: [CollectionIdentifier]], collapsed: [CollectionIdentifier: Bool], collections: [CollectionIdentifier: Collection], selected: CollectionIdentifier?, animated: Bool) {
        var snapshot = NSDiffableDataSourceSectionSnapshot<Collection>()
        self.add(children: root, to: nil, in: &snapshot, allChildren: children, allCollections: collections)

        let (collapsed, expanded) = self.separateExpandedFromCollapsed(collections: snapshot.items, collapsedState: collapsed)
        snapshot.collapse(collapsed)
        snapshot.expand(expanded)

        self.dataSource.apply(snapshot, to: 0, animatingDifferences: animated)
    }

    private func separateExpandedFromCollapsed(collections: [Collection], collapsedState: [CollectionIdentifier: Bool]) -> (collapsed: [Collection], expanded: [Collection]) {
        var collapsed: [Collection] = []
        var expanded: [Collection] = []

        for collection in collections {
            let isCollapsed = collapsedState[collection.identifier] ?? true
            if isCollapsed {
                collapsed.append(collection)
            } else {
                expanded.append(collection)
            }
        }

        return (collapsed, expanded)
    }

    private func add(children: [CollectionIdentifier], to parent: Collection?, in snapshot: inout NSDiffableDataSourceSectionSnapshot<Collection>,
                     allChildren: [CollectionIdentifier: [CollectionIdentifier]], allCollections: [CollectionIdentifier: Collection]) {
        guard !children.isEmpty else { return }

        let collections = children.compactMap({ allCollections[$0] })
        snapshot.append(collections, to: parent)

        for collection in collections {
            guard let children = allChildren[collection.identifier] else { continue }
            self.add(children: children, to: collection, in: &snapshot, allChildren: allChildren, allCollections: allCollections)
        }
    }

    private lazy var cellRegistration: UICollectionView.CellRegistration<CollectionCell, Collection> = {
        return UICollectionView.CellRegistration<CollectionCell, Collection> { [weak self] cell, indexPath, collection in
            guard let `self` = self else { return }

            let snapshot = self.dataSource.snapshot(for: self.collectionsSection)
            let hasChildren = snapshot.snapshot(of: collection, includingParent: false).items.count > 0

            var configuration = CollectionCell.ContentConfiguration(collection: collection, hasChildren: hasChildren)
            configuration.isCollapsedProvider = { [weak self] in
                guard let `self` = self else { return false }
                return !self.dataSource.snapshot(for: self.collectionsSection).isExpanded(collection)
            }
            configuration.toggleCollapsed = { [weak self, weak cell] in
                guard let `self` = self, let cell = cell else { return }
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
        snapshot.appendSections([0])
        dataSource.apply(snapshot, animatingDifferences: false)

        return dataSource
    }

    private func createCollectionViewLayout() -> UICollectionViewCompositionalLayout {
        return UICollectionViewCompositionalLayout { section, environment in
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
}
