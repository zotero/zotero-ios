//
//  ItemsViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 04/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjack
import RxSwift
import RealmSwift

class ItemsViewController: UIViewController {
    // Outlets
    @IBOutlet private weak var tableView: UITableView!
    // Constants
    private let store: ItemsStore
    private let disposeBag: DisposeBag

    // MARK: - Lifecycle

    init(store: ItemsStore) {
        self.store = store
        self.disposeBag = DisposeBag()
        super.init(nibName: "ItemsViewController", bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if UIDevice.current.userInterfaceIdiom == .phone {
            self.navigationItem.title = self.store.state.value.title
        }
        self.navigationItem.leftBarButtonItem = self.splitViewController?.displayModeButtonItem
        self.navigationItem.leftItemsSupplementBackButton = true
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
        self.navigationController?.splitViewController?.presentsWithGesture = true
    }

    // MARK: - Actions

    private func showItem(at indexPath: IndexPath) {
        guard let items = self.store.state.value.dataSource?.items(for: indexPath.section),
              indexPath.row < items.count else { return }

        do {
            let store = try ItemDetailStore(initialState: ItemDetailStore.StoreState(item: items[indexPath.row]),
                                            apiClient: self.store.apiClient,
                                            fileStorage: self.store.fileStorage,
                                            dbStorage: self.store.dbStorage,
                                            schemaController: self.store.schemaController)
            let controller = ItemDetailViewController(store: store)
            self.navigationController?.pushViewController(controller, animated: true)
        } catch let error {
            DDLogError("ItemsViewController: could not create ItemDewtailStore: \(error)")
            // TODO: - Show error message
        }
    }

    // MARK: - Setups

    private func setupTableView() {
        self.tableView.register(UINib(nibName: ItemCell.nibName, bundle: nil), forCellReuseIdentifier: "Cell")
        self.tableView.dataSource = self
        self.tableView.delegate = self
    }
}

extension ItemsViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return self.store.state.value.dataSource?.sectionCount ?? 0
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.store.state.value.dataSource?.items(for: section)?.count ?? 0
    }

    func sectionIndexTitles(for tableView: UITableView) -> [String]? {
        return self.store.state.value.dataSource?.sectionIndexTitles
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return ItemCell.height
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)

        guard let itemCell = cell as? ItemCell,
              let items = self.store.state.value.dataSource?.items(for: indexPath.section) else { return cell }

        itemCell.setup(with: items[indexPath.row])

        return cell
    }
}

extension ItemsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        self.showItem(at: indexPath)
    }
}

extension RItem: ItemCellModel {
    var creator: String? {
        return self.creatorSummary.isEmpty ? nil : self.creatorSummary
    }

    var date: String? {
        return self.parsedDate.isEmpty ? nil : self.parsedDate
    }

    var hasAttachment: Bool {
        return self.children.filter(Predicates.items(type: .attachment, notSyncState: .dirty)).count > 0
    }

    var hasNote: Bool {
        return self.children.filter(Predicates.items(type: .note, notSyncState: .dirty)).count > 0
    }

    var tagColors: [UIColor] {
        return self.tags.compactMap({ $0.uiColor })
    }

    var icon: UIImage? {
        return self.type.icon
    }
}
