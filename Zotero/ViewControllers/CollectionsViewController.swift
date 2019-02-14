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
    private weak var navigationDelegate: ItemNavigationDelegate?
    private var lastIndexPath: IndexPath?

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

        if let indexPath = self.lastIndexPath {
            self.tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
        }
    }

    // MARK: - Actions

    // MARK: - Setups

    private func setupTableView() {
        self.tableView.register(UINib(nibName: "CollectionCell", bundle: nil), forCellReuseIdentifier: "Cell")
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

        if indexPath.row < self.store.state.value.cellData.count,
           let cell = cell as? CollectionCell {
            let collection = self.store.state.value.cellData[indexPath.row]
            cell.setup(with: collection)
        }

        return cell
    }
}

extension CollectionsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        if indexPath.row == tableView.indexPathForSelectedRow?.row {
            tableView.deselectRow(at: indexPath, animated: false)
            self.lastIndexPath = nil
            let state = self.store.state.value
            self.navigationDelegate?.showItems(libraryData: (state.libraryId, state.title), collectionData: nil)
            return nil
        }
        return indexPath
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if UIDevice.current.userInterfaceIdiom == .phone {
            tableView.deselectRow(at: indexPath, animated: true)
        }
        self.lastIndexPath = indexPath
        let collection = self.store.state.value.cellData[indexPath.row]
        let state = self.store.state.value
        self.navigationDelegate?.showItems(libraryData: (state.libraryId, state.title),
                                           collectionData: (collection.identifier, collection.name))
    }
}

extension CollectionCellData: CollectionCellModel {}
