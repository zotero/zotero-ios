//
//  ItemsFilterViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 16.04.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class ItemsFilterViewController: UIViewController {
    private weak var container: UIView!
    private weak var containerTop: NSLayoutConstraint!
    private weak var separator: UIView!

    private static let downloadsHeight: CGFloat = 44
    private static let width: CGFloat = 320
    private let tagFilterController: TagFilterViewController
    private weak var mainCoordinatorDelegate: MainCoordinatorDelegate?

    private var downloadsFilterEnabled: Bool
    weak var delegate: DownloadsFilterDelegate?

    init(downloadsFilterEnabled: Bool, tagFilterController: TagFilterViewController, mainCoordinatorDelegate: MainCoordinatorDelegate) {
        self.downloadsFilterEnabled = downloadsFilterEnabled
        self.tagFilterController = tagFilterController
        self.mainCoordinatorDelegate = mainCoordinatorDelegate
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        setupNavigationBar()
        setupViews()
        showHideTagFilter()

        parent?.presentationController?.delegate = self

        func setupNavigationBar() {
            navigationItem.title = L10n.Items.Filters.title
            let primaryAction = UIAction(title: L10n.done) { [weak self] _ in
                self?.navigationController?.presentingViewController?.dismiss(animated: true)
            }
            let done: UIBarButtonItem
            if #available(iOS 26.0.0, *) {
                done = UIBarButtonItem(systemItem: .done, primaryAction: primaryAction)
                done.tintColor = Asset.Colors.zoteroBlue.color
            } else {
                done = UIBarButtonItem(primaryAction: primaryAction)
            }
            navigationItem.rightBarButtonItem = done
        }

        func setupViews() {
            let downloadsTitleLabel = UILabel()
            downloadsTitleLabel.font = .preferredFont(forTextStyle: .body)
            downloadsTitleLabel.text = L10n.Items.Filters.downloads
            downloadsTitleLabel.translatesAutoresizingMaskIntoConstraints = false

            let downloadsSwitch = UISwitch()
            downloadsSwitch.isOn = downloadsFilterEnabled
            downloadsSwitch.addAction(UIAction(handler: { [weak self] action in
                self?.delegate?.downloadsFilterDidChange(enabled: (action.sender as? UISwitch)?.isOn == true)
            }), for: .valueChanged)
            downloadsSwitch.translatesAutoresizingMaskIntoConstraints = false

            let container = UIView()
            container.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(downloadsTitleLabel)
            container.addSubview(downloadsSwitch)
            view.addSubview(container)
            self.container = container

            let separator = UIView()
            separator.backgroundColor = .opaqueSeparator
            separator.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(separator)
            self.separator = separator

            tagFilterController.willMove(toParent: self)
            view.addSubview(tagFilterController.view)
            addChild(tagFilterController)
            tagFilterController.didMove(toParent: self)

            containerTop = container.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 15)
            if #available(iOS 26.0.0, *) {
                NSLayoutConstraint.activate([
                    container.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor),
                    container.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
                    container.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
                    container.heightAnchor.constraint(equalToConstant: Self.downloadsHeight),
                    downloadsTitleLabel.topAnchor.constraint(equalTo: container.topAnchor),
                    downloadsTitleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                    downloadsTitleLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                    downloadsSwitch.leadingAnchor.constraint(equalTo: downloadsTitleLabel.trailingAnchor, constant: 12),
                    container.trailingAnchor.constraint(equalTo: downloadsSwitch.trailingAnchor),
                    downloadsSwitch.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                    separator.topAnchor.constraint(equalTo: container.bottomAnchor, constant: 4),
                    separator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                    separator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                    separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
                    tagFilterController.view.topAnchor.constraint(equalTo: container.bottomAnchor, constant: 15),
                    tagFilterController.view.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
                    tagFilterController.view.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
                    tagFilterController.view.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor)
                ])
            } else {
                NSLayoutConstraint.activate([
                    containerTop,
                    container.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
                    container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                    container.heightAnchor.constraint(equalToConstant: Self.downloadsHeight),
                    downloadsTitleLabel.topAnchor.constraint(equalTo: container.topAnchor),
                    downloadsTitleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                    downloadsTitleLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                    downloadsSwitch.leadingAnchor.constraint(equalTo: downloadsTitleLabel.trailingAnchor, constant: 12),
                    container.trailingAnchor.constraint(equalTo: downloadsSwitch.trailingAnchor, constant: 16),
                    downloadsSwitch.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                    separator.topAnchor.constraint(equalTo: container.bottomAnchor, constant: 4),
                    separator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                    separator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                    separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
                    tagFilterController.view.topAnchor.constraint(equalTo: container.bottomAnchor, constant: 15),
                    tagFilterController.view.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
                    tagFilterController.view.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
                    tagFilterController.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
                ])
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        showHideTagFilter()
        preferredContentSize = CGSize(width: Self.width, height: Self.downloadsHeight)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if #available(iOS 26.0, *) {
            navigationController?.setToolbarHidden(true, animated: false)
        }
    }

    // MARK: - Actions
    
    private func showHideTagFilter() {
        let hideTags = mainCoordinatorDelegate?.usesSidebarTagFilter == true
        tagFilterController.view.isHidden = hideTags
        separator.isHidden = hideTags
        if #available(iOS 26.0, *) {
            if !hideTags {
                tagFilterController.setupBottomToolbar(in: self)
            }
            navigationController?.setToolbarHidden(hideTags, animated: false)
        } else {
            containerTop.constant = hideTags ? 15 : 4
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
