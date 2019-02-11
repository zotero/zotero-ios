//
//  CollectionsViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 04/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class CollectionsViewController: UIViewController {
    // Outlets
    @IBOutlet private weak var tableView: UITableView!
    // Constants
    private let store: CollectionsStore
    private let disposeBag: DisposeBag
    // Variables
    private var selectedIndexPath: IndexPath?
    private weak var navigationDelegate: ItemNavigationDelegate?

    // MARK: - Lifecycle

    init(store: CollectionsStore, delegate: ItemNavigationDelegate?) {
        self.store = store
        self.navigationDelegate = delegate
        self.disposeBag = DisposeBag()
        super.init(nibName: "CollectionsViewController", bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationItem.title = self.store.state.value.title
        self.setupTableView()

        self.store.state.asObservable()
                        .observeOn(MainScheduler.instance)
                        .subscribe(onNext: { [weak self] state in
                            self?.tableView.reloadData()
                        })
                        .disposed(by: self.disposeBag)

        self.store.handle(action: .load)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if let indexPath = self.selectedIndexPath {
            self.tableView.deselectRow(at: indexPath, animated: false)
        }

        self.navigationDelegate?.showItems(libraryId: self.store.state.value.libraryId,
                                           collectionId: self.store.state.value.parentId)
    }

    // MARK: - Actions

    private func showCollections(for parentId: String, name: String) {
        let state = CollectionsState(libraryId: self.store.state.value.libraryId, parentId: parentId, title: name)
        let store = CollectionsStore(initialState: state, dbStorage: self.store.dbStorage)
        let controller = CollectionsViewController(store: store, delegate: self.navigationDelegate)
        self.navigationController?.pushViewController(controller, animated: true)
    }

    // MARK: - Setups

    private func setupTableView() {
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        self.tableView.dataSource = self
        self.tableView.delegate = self
    }
}

extension CollectionsViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.store.state.value.cellData.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)

        if indexPath.row < self.store.state.value.cellData.count {
            let collection = self.store.state.value.cellData[indexPath.row]
            cell.textLabel?.text = collection.name
        }

        return cell
    }
}

extension CollectionsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if self.selectedIndexPath == indexPath {
            tableView.deselectRow(at: indexPath, animated: true)
        }

        self.selectedIndexPath = indexPath
        let collection = self.store.state.value.cellData[indexPath.row]
        if collection.hasChildren {
            self.showCollections(for: collection.identifier, name: collection.name)
        } else {
            self.navigationDelegate?.showItems(libraryId: self.store.state.value.libraryId,
                                               collectionId: collection.identifier)
        }
    }

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        self.navigationDelegate?.showItems(libraryId: self.store.state.value.libraryId,
                                           collectionId: self.store.state.value.parentId)
    }
}
