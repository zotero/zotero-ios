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
    private static let defaultIndexPath: IndexPath = IndexPath(row: 0, section: 0)
    private let store: CollectionsStore
    private let disposeBag: DisposeBag
    // Variables
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
                            guard let `self` = self else { return }
                            let selectedIndexPath = self.tableView.indexPathForSelectedRow
                            self.tableView.reloadData()
                            if let indexPath = selectedIndexPath {
                                self.tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
                            }
                        })
                        .disposed(by: self.disposeBag)

        self.store.handle(action: .load)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if self.tableView.indexPathForSelectedRow == nil {
            self.tableView.selectRow(at: CollectionsViewController.defaultIndexPath,
                                     animated: false, scrollPosition: .none)
        }
    }

    // MARK: - Actions

    private func data(for section: Int) -> [CollectionCellData] {
        switch section {
        case 0:
            return self.store.state.value.allItemsCellData
        case 1:
            return self.store.state.value.collectionCellData
        case 2:
            return self.store.state.value.searchCellData
        case 3:
            return self.store.state.value.customCellData
        default:
            return []
        }
    }

    // MARK: - Setups

    private func setupTableView() {
        self.tableView.register(UINib(nibName: CollectionCell.nibName, bundle: nil), forCellReuseIdentifier: "Cell")
        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.contentInset = UIEdgeInsets(top: self.tableView.contentInset.top,
                                                   left: 0, bottom: 44, right: 0)
    }
}

extension CollectionsViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 4
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.data(for: section).count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)

        guard let collectionCell = cell as? CollectionCell else { return cell }

        let data = self.data(for: indexPath.section)
        if indexPath.row < data.count {
            collectionCell.setup(with: data[indexPath.row])
        }

        return cell
    }
}

extension CollectionsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if UIDevice.current.userInterfaceIdiom == .phone {
            tableView.deselectRow(at: indexPath, animated: true)
        }

        let state = self.store.state.value
        let data = self.data(for: indexPath.section)[indexPath.row]

        switch data.type {
        case .collection:
            self.navigationDelegate?.showCollectionItems(libraryId: state.libraryId,
                                                         collectionData: (data.key, data.name))
        case .search:
            self.navigationDelegate?.showSearchItems(libraryId: state.libraryId, searchData: (data.key, data.name))
        case .custom(let type):
            switch type {
            case .all:
                self.navigationDelegate?.showAllItems(for: state.libraryId)
            case .trash:
                self.navigationDelegate?.showTrashItems(for: state.libraryId)
            case .publications:
                self.navigationDelegate?.showPublications(for: state.libraryId)
            }
        }
    }
}

extension CollectionCellData: CollectionCellModel {
    var icon: UIImage? {
        let name: String
        switch self.type {
        case .collection(let hasChildren):
            name = "icon_cell_collection" + (hasChildren ? "s" : "")
        case .search:
            name = "icon_cell_document"
        case .custom(let type):
            switch type {
            case .all, .publications:
                name = "icon_cell_document"
            case .trash:
                name = "icon_cell_trash"
            }
        }

        return UIImage(named: name)?.withRenderingMode(.alwaysTemplate)
    }
}
