//
//  LibrariesViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 11/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class LibrariesViewController: UIViewController {
    // Outlets
    @IBOutlet private weak var tableView: UITableView!
    // Constants
    private let store: LibrariesStore
    private let disposeBag: DisposeBag
    // Variables
    private var selectedIndexPath: IndexPath?
    private weak var navigationDelegate: ItemNavigationDelegate?

    init(store: LibrariesStore, delegate: ItemNavigationDelegate) {
        self.store = store
        self.navigationDelegate = delegate
        self.disposeBag = DisposeBag()
        super.init(nibName: "LibrariesViewController", bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError()
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationItem.title = "Libraries"
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
            self.selectedIndexPath = nil
        }

        self.navigationDelegate?.hideItems()
    }

    // MARK: - Actions

    private func showLibrary(with identifier: Int, name: String) {
        let state = CollectionsState(libraryId: identifier, parentId: nil, title: name)
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

extension LibrariesViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.store.state.value.cellData.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)

        if indexPath.row < self.self.store.state.value.cellData.count {
            let library = self.self.store.state.value.cellData[indexPath.row]
            cell.textLabel?.text = library.name
        }

        return cell
    }
}

extension LibrariesViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        self.selectedIndexPath = indexPath
        let library = self.store.state.value.cellData[indexPath.row]
        self.showLibrary(with: library.identifier, name: library.name)
    }
}
