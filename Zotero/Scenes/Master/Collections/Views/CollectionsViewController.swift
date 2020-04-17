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
    private unowned let dbStorage: DbStorage
    private let disposeBag: DisposeBag

    private var tableViewHandler: CollectionsTableViewHandler!
    weak var coordinatorDelegate: MasterCollectionsCoordinatorDelegate?

    init(viewModel: ViewModel<CollectionsActionHandler>, dbStorage: DbStorage, dragDropController: DragDropController) {
        self.viewModel = viewModel
        self.dbStorage = dbStorage
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
        self.coordinatorDelegate?.collectionsChanged(to: self.viewModel.state.collections)

        self.viewModel.stateObservable
                      .observeOn(MainScheduler.instance)
                      .subscribe(onNext: { [weak self] state in
                          self?.update(to: state)
                      })
                      .disposed(by: self.disposeBag)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.selectCurrentRowIfNeeded()
        if self.coordinatorDelegate?.isSplit == true {
            self.coordinatorDelegate?.show(collection: self.viewModel.state.selectedCollection, in: self.viewModel.state.library)
        }
    }

    // MARK: - UI state

    private func update(to state: CollectionsState) {
        if state.changes.contains(.results) {
            self.tableViewHandler.update(collections: state.collections, animated: true, completed: { [weak self] in
                self?.selectCurrentRowIfNeeded()
            })
            self.coordinatorDelegate?.collectionsChanged(to: state.collections)
        }
        if state.changes.contains(.itemCount) {
            self.tableViewHandler.update(collections: state.collections, animated: false, completed: { [weak self] in
                self?.selectCurrentRowIfNeeded()
            })
        }
        if state.changes.contains(.selection) {
            self.coordinatorDelegate?.show(collection: state.selectedCollection, in: state.library)
        }
        if let data = state.editingData {
            self.coordinatorDelegate?.showEditView(for: data, library: state.library)
        }
    }

    private func selectCurrentRowIfNeeded() {
        guard self.coordinatorDelegate?.isSplit == true else { return }
        if let index = self.viewModel.state.collections.firstIndex(of: self.viewModel.state.selectedCollection) {
            self.tableView.selectRow(at: IndexPath(row: index, section: 0), animated: false, scrollPosition: .none)
        }
    }

    // MARK: - Actions

    @objc private func addCollection() {
        self.viewModel.process(action: .startEditing(.add))
    }

    // MARK: - Setups

    private func setupAddNavbarItem() {
        let item = UIBarButtonItem(image: UIImage(systemName: "plus"),
                                   style: .plain,
                                   target: self,
                                   action: #selector(CollectionsViewController.addCollection))
        self.navigationItem.rightBarButtonItem = item
    }
}
