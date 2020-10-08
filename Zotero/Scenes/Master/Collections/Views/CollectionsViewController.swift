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

        self.navigationItem.title = self.viewModel.state.library.name
        if self.viewModel.state.library.metadataEditable {
            self.setupAddNavbarItem()
        }
        self.tableViewHandler = CollectionsTableViewHandler(tableView: self.tableView,
                                                            viewModel: self.viewModel,
                                                            dragDropController: self.dragDropController,
                                                            splitDelegate: self.coordinatorDelegate)

        self.viewModel.process(action: .loadData)
        self.tableViewHandler.update(collections: self.viewModel.state.collections, animated: false)

        self.viewModel.stateObservable
                      .observeOn(MainScheduler.instance)
                      .subscribe(onNext: { [weak self] state in
                          self?.update(to: state)
                      })
                      .disposed(by: self.disposeBag)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.selectIfNeeded(collection: self.viewModel.state.selectedCollection)
        if self.coordinatorDelegate?.isSplit == true {
            self.coordinatorDelegate?.show(collection: self.viewModel.state.selectedCollection, in: self.viewModel.state.library)
        }
    }

    // MARK: - UI state

    private func update(to state: CollectionsState) {
        if state.changes.contains(.results) {
            self.tableViewHandler.update(collections: state.collections, animated: true, completed: { [weak self] in
                self?.selectIfNeeded(collection: state.selectedCollection)
            })
        }
        if state.changes.contains(.allItemCount) {
            self.tableViewHandler.updateAllItemCell(with: state.collections[0])
        }
        if state.changes.contains(.selection) {
            self.coordinatorDelegate?.show(collection: state.selectedCollection, in: state.library)
        }
        if let data = state.editingData {
            self.coordinatorDelegate?.showEditView(for: data, library: state.library)
        }
    }

    // MARK: - Actions

    private func showSearch() {
        let collections = self.viewModel.state.collections.filter({ !$0.type.isCustom })
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

    private func selectIfNeeded(collection: Collection) {
        // Selection is disabled in compact mode (when UISplitViewController is a single column instead of master + detail).
        guard self.coordinatorDelegate?.isSplit == true else { return }

        if let index = self.viewModel.state.collections.firstIndex(where: { $0.id == collection.id }) {
            guard self.tableView.indexPathForSelectedRow?.row != index else { return }
            self.tableView.selectRow(at: IndexPath(row: index, section: 0), animated: false, scrollPosition: .none)
        } else if let indexPath = self.tableView.indexPathForSelectedRow {
            self.tableView.deselectRow(at: indexPath, animated: false)
        }
    }

    private func select(searchResult: Collection) {
        let isSplit = self.coordinatorDelegate?.isSplit ?? false

        if isSplit {
            self.selectIfNeeded(collection: searchResult)
        }

        // We don't need to always show it on iPad, since the currently selected collection is visible. So we show only a new one. On iPhone
        // on the other hand we see only the collection list, so we always need to open the item list for selected collection.
        guard !isSplit ? true : searchResult.id != self.viewModel.state.selectedCollection.id else { return }
        self.viewModel.process(action: .select(searchResult))
    }

    // MARK: - Setups

    private func setupAddNavbarItem() {
        let addItem = UIBarButtonItem(image: UIImage(systemName: "plus"), style: .plain, target: nil, action: nil)
        addItem.rx
               .tap
               .subscribe(onNext: { [weak self] _ in
                   self?.viewModel.process(action: .startEditing(.add))
               })
               .disposed(by: self.disposeBag)

        let searchItem = UIBarButtonItem(image: UIImage(systemName: "magnifyingglass"), style: .plain, target: nil, action: nil)
        searchItem.rx
                  .tap
                  .subscribe(onNext: { [weak self] _ in
                    self?.showSearch()
                  })
                  .disposed(by: self.disposeBag)

        self.navigationItem.rightBarButtonItems = [addItem, searchItem]
    }
}
