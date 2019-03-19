//
//  CollectionPickerViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 19/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class CollectionPickerViewController: UIViewController {
    // Outlets
    @IBOutlet private weak var tableView: UITableView!
    // Constants
    private let store: CollectionPickerStore
    private let disposeBag: DisposeBag

    init(store: CollectionPickerStore) {
        self.store = store
        self.disposeBag = DisposeBag()
        super.init(nibName: "CollectionPickerViewController", bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupTableView()

        self.store.state.asObservable()
                        .observeOn(MainScheduler.instance)
                        .subscribe(onNext: { [weak self] state in
                            if state.changes.contains(.data) {
                                self?.tableView.reloadData()
                            }
                            if let error = state.error {
                                // TODO: - Show error
                            }
                        })
                        .disposed(by: self.disposeBag)

        self.store.handle(action: .load)
    }

    // MARK: - Setups

    private func setupTableView() {
        self.tableView.register(UINib(nibName: CollectionCell.nibName, bundle: nil), forCellReuseIdentifier: "Cell")
        self.tableView.dataSource = self
        self.tableView.delegate = self
    }
}

extension CollectionPickerViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.store.state.value.cellData.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)

        if let cell = cell as? CollectionCell {
            let model = self.store.state.value.cellData[indexPath.row]
            cell.setup(with: model)
        }

        return cell
    }
}

extension CollectionPickerViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        self.store.handle(action: .pick(indexPath.row))
    }
}
