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

protocol SplitControllerDelegate: AnyObject {
    var isSplit: Bool { get }
}

final class CollectionsViewController: UICollectionViewController {
    let viewModel: ViewModel<CollectionsActionHandler>
    private unowned let dbStorage: DbStorage
    private unowned let syncScheduler: SynchronizationScheduler
    private let disposeBag: DisposeBag

    private var collectionViewHandler: ExpandableCollectionsCollectionViewHandler!
    private weak var coordinatorDelegate: MasterCollectionsCoordinatorDelegate?
    private var refreshController: SyncRefreshController?
    var selectedCollectionId: CollectionIdentifier? {
        return self.viewModel.state.selectedCollectionId
    }

    init(
        viewModel: ViewModel<CollectionsActionHandler>,
        dbStorage: DbStorage,
        syncScheduler: SynchronizationScheduler,
        coordinatorDelegate: MasterCollectionsCoordinatorDelegate
    ) {
        self.viewModel = viewModel
        self.dbStorage = dbStorage
        self.syncScheduler = syncScheduler
        self.coordinatorDelegate = coordinatorDelegate
        self.disposeBag = DisposeBag()

        super.init(collectionViewLayout: UICollectionViewFlowLayout())

        self.viewModel.process(action: .loadData)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if let selectedCollectionId = viewModel.state.selectedCollectionId ?? (isSplit ? .custom(.all) : nil), let collection = viewModel.state.collectionTree.collection(for: selectedCollectionId) {
            coordinatorDelegate?.showItems(for: collection, in: viewModel.state.library.identifier)
        }

        self.setupTitleWithContextMenu(self.viewModel.state.library.name)
        if self.viewModel.state.library.metadataEditable {
            self.setupNavigationBar()
        }

        self.collectionViewHandler = ExpandableCollectionsCollectionViewHandler(
            collectionView: self.collectionView,
            dbStorage: dbStorage,
            viewModel: self.viewModel,
            splitDelegate: self
        )
        self.collectionViewHandler.update(with: self.viewModel.state.collectionTree, selectedId: self.viewModel.state.selectedCollectionId, animated: false)

        self.viewModel.stateObservable
                      .observe(on: MainScheduler.instance)
                      .subscribe(onNext: { [weak self] state in
                          self?.update(to: state)
                      })
                      .disposed(by: self.disposeBag)
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)

        if !isSplit {
            guard collectionView.refreshControl == nil else { return }
            // There is a UIKit but with UICollectionView and UIRefreshController. The indicator doesn't show up when you go back from items to collections screen. But if you go back again to
            // libraries and then go back forward to collections, it starts showing up again.
            refreshController = SyncRefreshController(libraryId: viewModel.state.library.identifier, view: collectionView, syncScheduler: syncScheduler)
        } else {
            refreshController = nil
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        if !self.collectionView.visibleCells.isEmpty && (self.collectionView.indexPathsForSelectedItems ?? []).isEmpty {
            self.selectIfNeeded(collectionId: self.viewModel.state.selectedCollectionId, tree: self.viewModel.state.collectionTree, scrollToPosition: true)
        }
    }

    // MARK: - UI state

    private func update(to state: CollectionsState) {
        let (requiresUpdate, animatedUpdate) = self.requiresDataSourceUpdate(state: state)

        if requiresUpdate {
            self.collectionViewHandler.update(with: state.collectionTree, selectedId: state.selectedCollectionId, animated: animatedUpdate) { [weak self] in
                self?.selectIfNeeded(collectionId: state.selectedCollectionId, tree: state.collectionTree, scrollToPosition: false)
            }
        }

        if state.changes.contains(.selection), let selectedCollectionId = state.selectedCollectionId, let collection = state.collectionTree.collection(for: selectedCollectionId) {
            Defaults.shared.selectedCollectionId = collection.identifier
            self.coordinatorDelegate?.showItems(for: collection, in: state.library.identifier)

            if !requiresUpdate {
                self.selectIfNeeded(collectionId: selectedCollectionId, tree: state.collectionTree, scrollToPosition: false)
            }
        }

        if state.changes.contains(.library) {
            setupNavigationBar()
        }

        if let data = state.editingData {
            self.coordinatorDelegate?.showEditView(for: data, library: state.library)
        }

        if let result = state.itemKeysForBibliography {
            switch result {
            case .success(let keys):
                self.coordinatorDelegate?.showCiteExport(for: keys, libraryId: state.library.identifier)

            case .failure:
                self.coordinatorDelegate?.showCiteExportError()
            }
        }
    }

    private func requiresDataSourceUpdate(state: CollectionsState) -> (requires: Bool, animated: Bool) {
        if state.changes.contains(.results) || state.changes.contains(.collapsedState) {
            return (true, true)
        }
        if state.changes.contains(.allItemCount) || state.changes.contains(.trashItemCount) || state.changes.contains(.unfiledItemCount) {
            return (true, false)
        }
        return (false, false)
    }

    // MARK: - Actions

    private func selectIfNeeded(collectionId: CollectionIdentifier?, tree: CollectionTree, scrollToPosition: Bool) {
        // Selection is disabled in compact mode (when UISplitViewController is a single column instead of master + detail).
        guard isSplit else { return }
        let collectionId = collectionId ?? .custom(.all)
        collectionViewHandler.selectIfNeeded(collectionId: collectionId, tree: tree, scrollToPosition: scrollToPosition)
    }

    private func select(searchResult: Collection) {
        // We don't need to always show it on iPad, since the currently selected collection is visible. So we show only a new one. On iPhone
        // on the other hand we see only the collection list, so we always need to open the item list for selected collection.
        guard !isSplit ? true : searchResult.identifier != self.viewModel.state.selectedCollectionId else { return }
        self.viewModel.process(action: .select(searchResult.identifier))
    }

    private func createCollapseAllContextMenu() -> UIMenu? {
        guard self.collectionViewHandler.hasExpandableCollection else { return nil }

        let allExpanded = self.collectionViewHandler.allCollectionsExpanded
        let selectedCollectionIsRoot = self.collectionViewHandler.selectedCollectionIsRoot
        let title = allExpanded ? L10n.Collections.collapseAll : L10n.Collections.expandAll
        let action = UIAction(title: title) { [weak self] _ in
            self?.viewModel.process(action: (allExpanded ? .collapseAll(selectedCollectionIsRoot: selectedCollectionIsRoot) : .expandAll(selectedCollectionIsRoot: selectedCollectionIsRoot)))
        }
    
        return UIMenu(title: "", children: [action])
    }

    // MARK: - Setups

    private func setupNavigationBar() {
        let searchItem = UIBarButtonItem(image: UIImage(systemName: "magnifyingglass"), style: .plain, target: nil, action: nil)
        searchItem.accessibilityLabel = L10n.Accessibility.Collections.searchCollections
        searchItem.rx.tap
            .subscribe(onNext: { [weak self] _ in
                guard let self else { return }
                coordinatorDelegate?.showSearch(for: viewModel.state, in: self, selectAction: { [weak self] collection in
                    self?.select(searchResult: collection)
                })
            })
            .disposed(by: disposeBag)

        var buttons: [UIBarButtonItem] = [searchItem]

        if viewModel.state.library.metadataEditable {
            let addItem = UIBarButtonItem(image: UIImage(systemName: "plus"), style: .plain, target: nil, action: nil)
            addItem.accessibilityLabel = L10n.Accessibility.Collections.createCollection
            addItem.rx.tap
                .subscribe(onNext: { [weak self] _ in
                    self?.viewModel.process(action: .startEditing(.add))
                })
                .disposed(by: disposeBag)
            buttons.append(addItem)
        }

        self.navigationItem.rightBarButtonItems = buttons
    }

    private func setupTitleWithContextMenu(_ title: String) {
        var configuration = UIButton.Configuration.plain()
        configuration.titleLineBreakMode = .byTruncatingTail
        configuration.attributedTitle = AttributedString(title, attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 17, weight: .semibold)]))
        configuration.baseForegroundColor = UIColor(dynamicProvider: { $0.userInterfaceStyle == .light ? .black : .white })
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        let button = UIButton(type: .custom)
        button.configuration = configuration
        button.accessibilityLabel = "\(title) \(L10n.Accessibility.Collections.expandAllCollections)"
        let interaction = UIContextMenuInteraction(delegate: self)
        button.addInteraction(interaction)
        self.navigationItem.titleView = button
    }
}

extension CollectionsViewController: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: { _ in
            return self.createCollapseAllContextMenu()
        })
    }
}

extension CollectionsViewController: BottomSheetObserver { }

extension CollectionsViewController: SplitControllerDelegate {
    var isSplit: Bool {
        // In iOS 26 split view controller is nil when this view loads for the first time.
        // We assume in that case that the view is split, as we want in any case for the collection items view controller to load.
        // In actual split view it shown as the detail, while in collapsed view it is pushed in the stack as the initially presented view controller.
        guard let splitViewController else { return true }
        return splitViewController.isCollapsed == false
    }
}
