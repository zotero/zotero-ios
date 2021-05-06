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

        guard let height = self.containerHeight else { return }

        height.constant = container.preferredContentSize.height

        guard self.didAppear else { return }

        UIView.animate(withDuration: 0.2) {
            self.view.layoutIfNeeded()
        }
    }

    private func setupForPad() {
        self.view.backgroundColor = ProcessInfo().operatingSystemVersion.majorVersion == 13 ? UIColor.black.withAlphaComponent(0.085) : .clear

        self.containerView.layer.cornerRadius = 8
        self.containerView.layer.masksToBounds = true

        let height = self.containerView.heightAnchor.constraint(equalToConstant: 100)
        height.priority = .defaultHigh
        self.containerHeight = height

        NSLayoutConstraint.activate([
            self.view.centerXAnchor.constraint(equalTo: self.containerView.centerXAnchor),
            self.view.centerYAnchor.constraint(equalTo: self.containerView.centerYAnchor),
            self.containerView.heightAnchor.constraint(lessThanOrEqualTo: self.view.heightAnchor),
            height,
            self.containerView.widthAnchor.constraint(equalToConstant: ContainerViewController.padWidth)
        ])
    }

    private func setupForPhone() {
        NSLayoutConstraint.activate([
            self.containerView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.containerView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.containerView.topAnchor.constraint(equalTo: self.view.topAnchor),
            self.containerView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])
    }
}
