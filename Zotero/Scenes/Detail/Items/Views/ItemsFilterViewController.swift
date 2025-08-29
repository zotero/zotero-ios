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
    private weak var container: UIView!
    private weak var containerTop: NSLayoutConstraint!
    private weak var separator: UIView!

    private static let downloadsHeight: CGFloat = 44
    private static let width: CGFloat = 320
    private let tagFilterController: TagFilterViewController
    private let disposeBag: DisposeBag

    weak var coordinatorDelegate: ItemsFilterCoordinatorDelegate?
    private var downloadsFilterEnabled: Bool
    weak var delegate: FiltersDelegate?

    init(downloadsFilterEnabled: Bool, tagFilterController: TagFilterViewController) {
        self.downloadsFilterEnabled = downloadsFilterEnabled
        self.tagFilterController = tagFilterController
        disposeBag = DisposeBag()
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
            let done = UIBarButtonItem(title: L10n.done)
            done.rx.tap
                .subscribe(onNext: { [weak self] _ in
                    self?.navigationController?.presentingViewController?.dismiss(animated: true)
                })
                .disposed(by: disposeBag)
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

        preferredContentSize = CGSize(width: Self.width, height: Self.downloadsHeight)
    }

    // MARK: - Actions
    
    private func showHideTagFilter() {
        let isCollapsed = (presentingViewController as? MainViewController)?.isCollapsed
        if UIDevice.current.userInterfaceIdiom == .phone || isCollapsed == true {
            tagFilterController.view.isHidden = false
            separator.isHidden = false
            if #unavailable(iOS 26.0.0) {
                containerTop.constant = 4
            }
        } else {
            tagFilterController.view.isHidden = true
            separator.isHidden = true
            if #unavailable(iOS 26.0.0) {
                containerTop.constant = 15
            }
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
