//
//  ItemsFilterViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 16.04.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class ItemsFilterViewController: UIViewController {
    @IBOutlet private weak var downloadsTitleLabel: UILabel!
    @IBOutlet private weak var downloadsSwitch: UISwitch!

    private let viewModel: ViewModel<ItemsActionHandler>

    init(viewModel: ViewModel<ItemsActionHandler>) {
        self.viewModel = viewModel
        super.init(nibName: "ItemsFilterViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupNavigationBar()
        self.setupFilters()

        let preferredSize = CGSize(width: 320, height: 88)
        self.preferredContentSize = preferredSize
        self.navigationController?.preferredContentSize = preferredSize
    }

    // MARK: - Actions

    @IBAction private func toggleDownloads(sender: UISwitch) {
        if sender.isOn {
            self.viewModel.process(action: .filter([.downloadedFiles]))
        } else {
            self.viewModel.process(action: .filter([]))
        }
    }

    @objc private func done() {
        self.navigationController?.presentingViewController?.dismiss(animated: true, completion: nil)
    }

    // MARK: - Setups

    private func setupNavigationBar() {
        self.navigationItem.title = L10n.Items.Filters.title
        let done = UIBarButtonItem(title: L10n.done, style: .done, target: self, action: #selector(ItemsFilterViewController.done))
        self.navigationItem.rightBarButtonItem = done
    }

    private func setupFilters() {
        self.downloadsTitleLabel.text = L10n.Items.Filters.downloads
        self.downloadsSwitch.isOn = !self.viewModel.state.filters.isEmpty
    }
}
