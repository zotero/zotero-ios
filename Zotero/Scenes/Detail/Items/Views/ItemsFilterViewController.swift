//
//  ItemsFilterViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 16.04.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class ItemsFilterViewController: UIViewController {
    @IBOutlet private weak var container: UIStackView!
    @IBOutlet private weak var containerTop: NSLayoutConstraint!
    @IBOutlet private weak var downloadsTitleLabel: UILabel!
    @IBOutlet private weak var downloadsSwitch: UISwitch!
    @IBOutlet private weak var separator: UIView!
    @IBOutlet private weak var tagFilterControllerContainer: UIView!

    private static let width: CGFloat = 320
    private let viewModel: ViewModel<ItemsActionHandler>
    private let tagFilterController: TagFilterViewController
    private let disposeBag: DisposeBag

    weak var coordinatorDelegate: ItemsFilterCoordinatorDelegate?
    private var downloadsFilterEnabled: Bool {
        return self.viewModel.state.filters.contains(where: { filter in
            switch filter {
            case .downloadedFiles: return true
            default: return false
            }
        })
    }

    init(viewModel: ViewModel<ItemsActionHandler>, tagFilterController: TagFilterViewController) {
        self.viewModel = viewModel
        self.tagFilterController = tagFilterController
        self.disposeBag = DisposeBag()
        super.init(nibName: "ItemsFilterViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupNavigationBar()
        self.setupUI()

        self.viewModel.stateObservable
                      .observe(on: MainScheduler.instance)
                      .subscribe(with: self, onNext: { `self`, state in
                          self.update(state: state)
                      })
                      .disposed(by: self.disposeBag)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        guard UIDevice.current.userInterfaceIdiom == .pad else { return }

        var preferredSize = self.container.systemLayoutSizeFitting(CGSize(width: ItemsFilterViewController.width, height: .greatestFiniteMagnitude))
        preferredSize.width = ItemsFilterViewController.width
        self.preferredContentSize = preferredSize
        self.navigationController?.preferredContentSize = preferredSize
    }

    // MARK: - Actions

    private func update(state: ItemsState) {
    }

    @IBAction private func toggleDownloads(sender: UISwitch) {
        if sender.isOn {
            self.viewModel.process(action: .enableFilter(.downloadedFiles))
        } else {
            self.viewModel.process(action: .disableFilter(.downloadedFiles))
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

    private func setupUI() {
        self.downloadsTitleLabel.text = L10n.Items.Filters.downloads
        self.downloadsSwitch.isOn = self.downloadsFilterEnabled

        guard UIDevice.current.userInterfaceIdiom == .phone else {
            self.tagFilterControllerContainer.isHidden = true
            self.separator.isHidden = true
            return
        }

        self.containerTop.constant = 4
        self.tagFilterController.willMove(toParent: self)
        self.tagFilterControllerContainer.addSubview(self.tagFilterController.view)
        self.addChild(self.tagFilterController)
        self.tagFilterController.didMove(toParent: self)

        NSLayoutConstraint.activate([
            self.tagFilterControllerContainer.leadingAnchor.constraint(equalTo: self.tagFilterController.view.leadingAnchor),
            self.tagFilterControllerContainer.trailingAnchor.constraint(equalTo: self.tagFilterController.view.trailingAnchor),
            self.tagFilterControllerContainer.topAnchor.constraint(equalTo: self.tagFilterController.view.topAnchor),
            self.tagFilterControllerContainer.bottomAnchor.constraint(equalTo: self.tagFilterController.view.bottomAnchor),
            self.separator.heightAnchor.constraint(equalToConstant: 1/UIScreen.main.scale)
        ])
    }
}
