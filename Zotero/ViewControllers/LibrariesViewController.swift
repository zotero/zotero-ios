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
            self.navigationDelegate?.showAllItems(for: RLibrary.myLibraryId)
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
        self.tableView.contentInset = UIEdgeInsets(top: self.tableView.contentInset.top,
                                                   left: 0, bottom: 44, right: 0)
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

        var title: String?
        switch indexPath.section {
        case 0:
            title = self.store.state.value.myLibrary.name
        case 1:
            if indexPath.row < self.self.store.state.value.groupLibraries.count {
                let library = self.self.store.state.value.groupLibraries[indexPath.row]
                title = library.name
            }
        default: break
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

        let library = indexPath.section == 0 ? self.store.state.value.myLibrary :
                                               self.store.state.value.groupLibraries[indexPath.row]
        self.navigationDelegate?.showCollections(for: library.identifier, libraryName: library.name)
        if UIDevice.current.userInterfaceIdiom == .pad {
            self.navigationDelegate?.showAllItems(for: library.identifier)
        }
    }
}
