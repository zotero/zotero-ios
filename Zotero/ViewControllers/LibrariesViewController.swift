//
//  LibrariesViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 11/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class LibrariesViewController: UIViewController, ProgressToolbarController {
    // Outlets
    @IBOutlet private weak var tableView: UITableView!
    // Constants
    private let store: LibrariesStore
    private let disposeBag: DisposeBag
    // Variables
    weak var toolbarTitleLabel: UILabel?
    weak var toolbarSubtitleLabel: UILabel?
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
        self.navigationItem.backBarButtonItem = UIBarButtonItem(title: nil, style: .plain, target: nil, action: nil)
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
            self.navigationDelegate?.showAllItems(for: .custom(.myLibrary))
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
        self.tableView.register(UINib(nibName: LibraryCell.nibName, bundle: nil),
                                forCellReuseIdentifier: "Cell")
        self.tableView.dataSource = self
        self.tableView.delegate = self
    }
}

extension LibrariesViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return self.store.state.value.sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch self.store.state.value.sections[section] {
        case .custom:
            return self.store.state.value.customLibraries.count
        case .groups:
            return self.store.state.value.groupLibraries.count
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return self.store.state.value.sections[section] == .groups ? "Group Libraries" : nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let state = self.store.state.value
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)

        var title: String?
        switch state.sections[indexPath.section] {
        case .custom:
            if indexPath.row < state.customLibraries.count {
                title = state.customLibraries[indexPath.row].name
            }
        case .groups:
            if indexPath.row < state.groupLibraries.count {
                title = state.groupLibraries[indexPath.row].name
            }
        }

        if let cell = cell as? LibraryCell,
           let title = title {
            cell.setup(with: title)
        }

        return cell
    }
}

extension LibrariesViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let data: LibraryCellData
        switch self.store.state.value.sections[indexPath.section] {
        case .custom:
            data = self.store.state.value.customLibraries[indexPath.row]
        case .groups:
            data = self.store.state.value.groupLibraries[indexPath.row]
        }

        self.navigationDelegate?.showCollections(for: data.identifier, libraryName: data.name)
        if UIDevice.current.userInterfaceIdiom == .pad {
            self.navigationDelegate?.showAllItems(for: data.identifier)
        }
    }
}
