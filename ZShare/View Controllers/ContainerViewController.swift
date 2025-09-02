//
//  ContainerViewController.swift
//  ZShare
//
//  Created by Michal Rentka on 18.01.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class ContainerViewController: UIViewController {
    @IBOutlet private weak var containerView: UIView!

    private weak var containerHeight: NSLayoutConstraint?
    private var didAppear = false

    private static let padWidth: CGFloat = 500

    override func viewDidLoad() {
        super.viewDidLoad()

        if UIDevice.current.userInterfaceIdiom == .pad {
            setupForPad()
        } else {
            setupForPhone()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        didAppear = true
    }

    override func preferredContentSizeDidChange(forChildContentContainer container: UIContentContainer) {
        super.preferredContentSizeDidChange(forChildContentContainer: container)

        guard let containerHeight else { return }

        containerHeight.constant = container.preferredContentSize.height

        guard didAppear else { return }

        UIView.animate(withDuration: 0.2) {
            self.view.layoutIfNeeded()
        }
    }

    private func setupForPad() {
        view.backgroundColor = .clear

        containerView.layer.cornerRadius = 8
        containerView.layer.masksToBounds = true

        let containerHeight = containerView.heightAnchor.constraint(equalToConstant: 100)
        containerHeight.priority = .defaultHigh
        self.containerHeight = containerHeight

        NSLayoutConstraint.activate([
            view.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            view.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            containerView.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor),
            containerHeight,
            containerView.widthAnchor.constraint(equalToConstant: Self.padWidth)
        ])
    }

    private func setupForPhone() {
        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.topAnchor.constraint(equalTo: view.topAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}
