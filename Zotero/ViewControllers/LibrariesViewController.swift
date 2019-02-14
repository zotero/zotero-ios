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

        if UIDevice.current.userInterfaceIdiom == .pad {
            self.navigationDelegate?.showItems(libraryData: (RLibrary.myLibraryId, "My Library"), collectionData: nil)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if UIDevice.current.userInterfaceIdiom == .pad {
            self.navigationDelegate?.didShowLibraries()
        }
    }

    // MARK: - Actions

    // MARK: - Setups

    private func setupTableView() {
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        self.tableView.dataSource = self
        self.tableView.delegate = self
    }
}

extension LibrariesViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            return 1
        case 1:
            return self.store.state.value.groupLibraries.count
        default:
             return 0
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return section == 1 ? "Group Libraries" : nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)

        switch indexPath.section {
        case 0:
            cell.textLabel?.text = self.store.state.value.myLibrary.name
        case 1:
            if indexPath.row < self.self.store.state.value.groupLibraries.count {
                let library = self.self.store.state.value.groupLibraries[indexPath.row]
                cell.textLabel?.text = library.name
            }
        default: break
        }

        return cell
    }
}

extension LibrariesViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let library = indexPath.section == 0 ? self.store.state.value.myLibrary :
                                               self.store.state.value.groupLibraries[indexPath.row]
        self.navigationDelegate?.showCollections(for: library.identifier, libraryName: library.name)
        if UIDevice.current.userInterfaceIdiom == .pad {
            self.navigationDelegate?.showItems(libraryData: (library.identifier, library.name), collectionData: nil)
        }
    }
}
