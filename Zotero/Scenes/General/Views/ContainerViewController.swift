//
//  ContainerViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 20.05.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class ContainerViewController: UIViewController {
    private let rootViewController: UIViewController

    private weak var containerHeight: NSLayoutConstraint?
    private weak var containerWidth: NSLayoutConstraint?
    private var didAppear = false

    // MARK: - Lifecycle

    init(rootViewController: UIViewController) {
        self.rootViewController = rootViewController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.preferredContentSize = UIScreen.main.bounds.size
        self.view.backgroundColor = .clear
        self.setupRootViewController()
        if UIDevice.current.userInterfaceIdiom == .pad {
            self.setupForPad()
        } else {
            self.setupForPhone()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.didAppear = true
    }

    override func preferredContentSizeDidChange(forChildContentContainer container: UIContentContainer) {
        super.preferredContentSizeDidChange(forChildContentContainer: container)

        guard let height = self.containerHeight, let width = self.containerWidth else { return }

        height.constant = container.preferredContentSize.height
        width.constant = container.preferredContentSize.width

        guard self.didAppear else { return }

        UIView.animate(withDuration: 0.2) {
            self.view.layoutIfNeeded()
        }
    }

    // MARK: - Actions

    @objc private func hide() {
        self.presentingViewController?.dismiss(animated: true, completion: nil)
    }

    // MARK: - Setups

    private func setupForPad() {
        self.setupTappableBackground()

        self.rootViewController.view.layer.cornerRadius = 8
        self.rootViewController.view.layer.masksToBounds = true

        let height = self.rootViewController.view.heightAnchor.constraint(equalToConstant: 100)
        height.priority = .defaultHigh
        self.containerHeight = height

        let width = self.rootViewController.view.widthAnchor.constraint(equalToConstant: 100)
        width.priority = .defaultHigh
        self.containerWidth = width

        NSLayoutConstraint.activate([
            self.view.centerXAnchor.constraint(equalTo: self.rootViewController.view.centerXAnchor),
            self.view.centerYAnchor.constraint(equalTo: self.rootViewController.view.centerYAnchor),
            self.rootViewController.view.heightAnchor.constraint(lessThanOrEqualTo: self.view.heightAnchor),
            height,
            width
        ])
    }

    private func setupForPhone() {
        NSLayoutConstraint.activate([
            self.rootViewController.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.rootViewController.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.rootViewController.view.topAnchor.constraint(equalTo: self.view.topAnchor),
            self.rootViewController.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])
    }

    private func setupRootViewController() {
        self.rootViewController.willMove(toParent: self)
        self.addChild(self.rootViewController)
        self.rootViewController.view.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(self.rootViewController.view)
        self.rootViewController.didMove(toParent: self)
    }

    private func setupTappableBackground() {
        let button = UIButton()
        button.addTarget(self, action: #selector(ContainerViewController.hide), for: .touchDown)

        button.frame = self.view.bounds
        button.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view.insertSubview(button, at: 0)
    }
}
