//
//  ItemDetailViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 19/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class ItemDetailViewController: UIViewController {
    // Outlets
    @IBOutlet private weak var tableView: UITableView!
    // Constants
    private let store: ItemDetailStore
    private let disposeBag: DisposeBag

    // MARK: - Lifecycle

    init(store: ItemDetailStore) {
        self.store = store
        self.disposeBag = DisposeBag()
        super.init(nibName: "ItemDetailViewController", bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationItem.title = self.store.state.value.item.title
        self.setupTableView()

        self.store.state.asObservable()
                        .observeOn(MainScheduler.instance)
                        .subscribe(onNext: { [weak self] state in
                            self?.tableView.reloadData()
                        })
                        .disposed(by: self.disposeBag)

        self.store.handle(action: .load)
    }

    // MARK: - Setups

    private func setupTableView() {
        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.register(UINib(nibName: ItemFieldCell.nibName, bundle: nil),
                                forCellReuseIdentifier: ItemFieldCell.nibName)
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "AttachmentCell")
    }
}

extension ItemDetailViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            return self.store.state.value.fields.count
        case 1:
            return self.store.state.value.attachments.count
        default:
            return 0
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0:
            return "Info"
        case 1:
            return "Attachments"
        default:
            return nil
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let identifier = indexPath.section == 0 ? ItemFieldCell.nibName : "AttachmentCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier, for: indexPath)

        if let cell = cell as? ItemFieldCell {
            if indexPath.row < self.store.state.value.fields.count {
                let field = self.store.state.value.fields[indexPath.row]
                cell.setup(with: field)
            }
        } else {
            if indexPath.row < self.store.state.value.attachments.count {
                let attachment = self.store.state.value.attachments[indexPath.row]
                cell.textLabel?.text = attachment.title
            }
        }

        return cell
    }
}

extension ItemDetailViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

extension ItemDetailField: ItemFieldCellModel {
    var title: String {
        return self.name
    }
}
