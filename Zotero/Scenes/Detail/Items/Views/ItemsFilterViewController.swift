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
    private let tagFilterController: TagFilterViewController
    private let disposeBag: DisposeBag

    weak var coordinatorDelegate: ItemsFilterCoordinatorDelegate?
    private var downloadsFilterEnabled: Bool
    weak var delegate: FiltersDelegate?

    init(downloadsFilterEnabled: Bool, tagFilterController: TagFilterViewController) {
        self.downloadsFilterEnabled = downloadsFilterEnabled
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
        
        parent?.presentationController?.delegate = self
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        var preferredSize = self.container.systemLayoutSizeFitting(CGSize(width: ItemsFilterViewController.width, height: .greatestFiniteMagnitude))
        preferredSize.width = ItemsFilterViewController.width
        self.preferredContentSize = preferredSize
        self.navigationController?.preferredContentSize = preferredSize
    }

    // MARK: - Actions

    @IBAction private func toggleDownloads(sender: UISwitch) {
        delegate?.downloadsFilterDidChange(enabled: sender.isOn)
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

        self.tagFilterController.willMove(toParent: self)
        self.tagFilterControllerContainer.addSubview(self.tagFilterController.view)
        self.addChild(self.tagFilterController)
        self.tagFilterController.didMove(toParent: self)

        NSLayoutConstraint.activate([
            self.tagFilterControllerContainer.leadingAnchor.constraint(equalTo: self.tagFilterController.view.leadingAnchor),
            self.tagFilterControllerContainer.trailingAnchor.constraint(equalTo: self.tagFilterController.view.trailingAnchor),
            self.tagFilterControllerContainer.topAnchor.constraint(equalTo: self.tagFilterController.view.topAnchor),
            self.tagFilterControllerContainer.bottomAnchor.constraint(equalTo: self.tagFilterController.view.bottomAnchor),
            self.separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
        ])
        
        showHideTagFilter()
    }
    
    func showHideTagFilter() {
        let isCollapsed = (presentingViewController as? MainViewController)?.isCollapsed
        if UIDevice.current.userInterfaceIdiom == .phone || isCollapsed == true {
            tagFilterControllerContainer.isHidden = false
            separator.isHidden = false
            containerTop.constant = 4
        } else {
            tagFilterControllerContainer.isHidden = true
            separator.isHidden = true
            containerTop.constant = 15
        }
    }
}

extension ItemsFilterViewController: UIAdaptivePresentationControllerDelegate {
    func presentationController(
        _ presentationController: UIPresentationController,
        willPresentWithAdaptiveStyle style: UIModalPresentationStyle,
        transitionCoordinator: UIViewControllerTransitionCoordinator?
    ) {
        if let transitionCoordinator {
            transitionCoordinator.animate { _ in
                self.showHideTagFilter()
            }
        } else {
            UIView.animate(withDuration: 0.1) {
                self.showHideTagFilter()
            }
        }
    }
}
