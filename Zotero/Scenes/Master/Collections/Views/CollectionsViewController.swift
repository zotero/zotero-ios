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

final class CollectionsViewController: UIViewController {
    @IBOutlet private weak var tableView: UITableView!

    private static let cellId = "CollectionRow"
    private let viewModel: ViewModel<CollectionsActionHandler>
    private unowned let dragDropController: DragDropController
    private let disposeBag: DisposeBag

    private var tableViewHandler: CollectionsTableViewHandler!
    weak var coordinatorDelegate: MasterCollectionsCoordinatorDelegate?

    init(viewModel: ViewModel<CollectionsActionHandler>, dragDropController: DragDropController) {
        self.viewModel = viewModel
        self.dragDropController = dragDropController
        self.disposeBag = DisposeBag()

        super.init(nibName: "CollectionsViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.viewModel.process(action: .loadData)

        self.setupTitleWithContextMenu(self.viewModel.state.library.name)
        if self.viewModel.state.library.metadataEditable {
            self.setupAddNavbarItem()
        }
        self.tableViewHandler = CollectionsTableViewHandler(tableView: self.tableView,
                                                            viewModel: self.viewModel,
                                                            dragDropController: self.dragDropController,
                                                            splitDelegate: self.coordinatorDelegate)

        self.tableViewHandler.updateCollections(animated: false)

        self.viewModel.stateObservable
                      .observe(on: MainScheduler.instance)
                      .subscribe(onNext: { [weak self] state in
                          self?.update(to: state)
                      })
                      .disposed(by: self.disposeBag)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.selectIfNeeded(collectionId: self.viewModel.state.selectedCollectionId, scrollToPosition: true)
        if self.coordinatorDelegate?.isSplit == true, let collection = self.viewModel.state.collections.first(where: { $0.identifier == self.viewModel.state.selectedCollectionId }) {
            self.coordinatorDelegate?.showItems(for: collection, in: self.viewModel.state.library, isInitial: true)
        }
    }

    // MARK: - UI state

    private func update(to state: CollectionsState) {
        if state.changes.contains(.results) {
            self.tableViewHandler.updateCollections(animated: true, completed: { [weak self] in
                self?.selectIfNeeded(collectionId: state.selectedCollectionId, scrollToPosition: false)
            })
        }
        if state.changes.contains(.allItemCount) {
            self.tableViewHandler.updateAllItemCell()
        }
        if state.changes.contains(.trashItemCount) {
            self.tableViewHandler.updateTrashItemCell()
        }
        if state.changes.contains(.selection), let collection = state.collections.first(where: { $0.identifier == state.selectedCollectionId }) {
            self.coordinatorDelegate?.showItems(for: collection, in: state.library, isInitial: false)
        }
        if let data = state.editingData {
            self.coordinatorDelegate?.showEditView(for: data, library: state.library)
        }
        if let result = state.itemKeysForBibliography {
            switch result {
            case .success(let keys):
                self.coordinatorDelegate?.showCiteExport(for: keys, libraryId: state.libraryId)
            case .failure:
                self.coordinatorDelegate?.showCiteExportError()
            }
        }
    }

    // MARK: - Actions

    private func showSearch() {
        let collections = self.viewModel.state.collections.filter({ !$0.identifier.isCustom })
                                                          .map({ SearchableCollection(isActive: true, collection: $0) })
        let viewModel = ViewModel(initialState: CollectionsSearchState(collections: collections), handler: CollectionsSearchActionHandler())
        let controller = CollectionsSearchViewController(viewModel: viewModel, selectAction: { [weak self] collection in
            self?.select(searchResult: collection)
        })
        controller.modalPresentationStyle = .overCurrentContext
        controller.modalTransitionStyle = .crossDissolve
        controller.isModalInPresentation = true
        self.present(controller, animated: true, completion: nil)
    }

    private func selectIfNeeded(collectionId: CollectionIdentifier, scrollToPosition: Bool) {
        // Selection is disabled in compact mode (when UISplitViewController is a single column instead of master + detail).
        guard self.coordinatorDelegate?.isSplit == true else { return }
        self.tableViewHandler.selectIfNeeded(collectionId: collectionId, scrollToPosition: scrollToPosition)
    }

    private func select(searchResult: Collection) {
        let isSplit = self.coordinatorDelegate?.isSplit ?? false

        if isSplit {
            self.selectIfNeeded(collectionId: searchResult.identifier, scrollToPosition: false)
        }

        // We don't need to always show it on iPad, since the currently selected collection is visible. So we show only a new one. On iPhone
        // on the other hand we see only the collection list, so we always need to open the item list for selected collection.
        guard !isSplit ? true : searchResult.identifier != self.viewModel.state.selectedCollectionId else { return }
        self.viewModel.process(action: .select(searchResult.identifier))
    }

    private func createCollapseAllContextMenu() -> UIMenu? {
        guard self.viewModel.state.hasExpandableCollection else { return nil }
        let allExpanded = self.viewModel.state.areAllExpanded
        let title = allExpanded ? L10n.Collections.collapseAll : L10n.Collections.expandAll
        let action = UIAction(title: title) { [weak self] _ in
            self?.viewModel.process(action: (allExpanded ? .collapseAll : .expandAll))
        }
        return UIMenu(title: "", children: [action])
    }

    // MARK: - Setups

    private func setupAddNavbarItem() {
        let addItem = UIBarButtonItem(image: UIImage(systemName: "plus"), style: .plain, target: nil, action: nil)
        addItem.accessibilityLabel = L10n.Accessibility.Collections.createCollection
        addItem.rx.tap
               .subscribe(onNext: { [weak self] _ in
                self?.viewModel.process(action: .startEditing(.add))
               })
               .disposed(by: self.disposeBag)

        let searchItem = UIBarButtonItem(image: UIImage(systemName: "magnifyingglass"), style: .plain, target: nil, action: nil)
        searchItem.accessibilityLabel = L10n.Accessibility.Collections.searchCollections
        searchItem.rx.tap
                  .subscribe(onNext: { [weak self] _ in
                    self?.showSearch()
                  })
                  .disposed(by: self.disposeBag)

        self.navigationItem.rightBarButtonItems = [addItem, searchItem]
    }

    private func setupTitleWithContextMenu(_ title: String) {
        let button = UIButton(type: .custom)
        button.setTitle(title, for: .normal)
        button.accessibilityLabel = "\(title) \(L10n.Accessibility.Collections.expandAllCollections)"
        button.setTitleColor(UIColor(dynamicProvider: { $0.userInterfaceStyle == .light ? .black : .white }), for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
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
