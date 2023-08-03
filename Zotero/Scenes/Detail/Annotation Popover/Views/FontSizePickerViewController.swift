//
//  FontSizePickerViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 01.08.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class FontSizePickerViewController: UIViewController {
    private static let sizes: [UInt] = [
        10,
        12,
        14,
        18,
        24,
        36,
        48,
        64,
        72,
        96,
        144,
        192
    ]

    private let pickAction: (UInt) -> Void

    private weak var tableView: UITableView!
    private var dataSource: UITableViewDiffableDataSource<Int, UInt>!

    init(pickAction: @escaping (UInt) -> Void) {
        self.pickAction = pickAction
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupViews()
        self.setupSizes()
    }

    override func loadView() {
        self.view = UIView()
    }

    private func setupSizes() {
        var snapshot = NSDiffableDataSourceSnapshot<Int, UInt>()
        snapshot.appendSections([0])
        snapshot.appendItems(FontSizePickerViewController.sizes)
        self.dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func setupViews() {
        let tableView = UITableView()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        self.dataSource = UITableViewDiffableDataSource(tableView: tableView, cellProvider: { tableView, indexPath, size in
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            var configuration = cell.defaultContentConfiguration()
            configuration.text = "\(size)pt"
            cell.contentConfiguration = configuration
            return cell
        })
        tableView.dataSource = self.dataSource
        tableView.delegate = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(tableView)

        NSLayoutConstraint.activate([
            self.view.leadingAnchor.constraint(equalTo: tableView.leadingAnchor),
            self.view.trailingAnchor.constraint(equalTo: tableView.trailingAnchor),
            self.view.topAnchor.constraint(equalTo: tableView.topAnchor),
            self.view.bottomAnchor.constraint(equalTo: tableView.bottomAnchor)
        ])
    }
}

extension FontSizePickerViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let size = self.dataSource.itemIdentifier(for: indexPath) else { return }
        self.pickAction(size)
        if let controller = self.presentingViewController {
            controller.dismiss(animated: true)
        } else {
            self.navigationController?.popViewController(animated: true)
        }
    }
}
