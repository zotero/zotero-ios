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
    private var constraints: [NSLayoutConstraint] = []
    private var didAppear = false

    private static let regularWidth: CGFloat = 500

    override func viewDidLoad() {
        super.viewDidLoad()

        setupLayoutForCurrentTraits()
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

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.horizontalSizeClass != traitCollection.horizontalSizeClass else { return }
        clearLayout()
        setupLayoutForCurrentTraits()

        func clearLayout() {
            NSLayoutConstraint.deactivate(constraints)
            constraints = []
            containerHeight = nil
        }
    }

    private func setupLayoutForCurrentTraits() {
        switch traitCollection.horizontalSizeClass {
        case .regular:
            constraints = setupForHorizontalSizeClassRegular()

        case .compact:
            constraints = setupForHorizontalSizeClassCompact()

        case .unspecified:
            break

        @unknown default:
            break
        }

        func setupForHorizontalSizeClassRegular() -> [NSLayoutConstraint] {
            view.backgroundColor = .clear

            containerView.layer.cornerRadius = 8
            containerView.layer.masksToBounds = true

            let containerHeight = containerView.heightAnchor.constraint(equalToConstant: 100)
            containerHeight.priority = .defaultHigh
            self.containerHeight = containerHeight

            let constraints = [
                containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                containerView.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor),
                containerHeight,
                containerView.widthAnchor.constraint(equalToConstant: Self.regularWidth)
            ]
            NSLayoutConstraint.activate(constraints)
            return constraints
        }

        func setupForHorizontalSizeClassCompact() -> [NSLayoutConstraint] {
            containerView.layer.cornerRadius = 0
            containerView.layer.masksToBounds = false

            let constraints = [
                containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                containerView.topAnchor.constraint(equalTo: view.topAnchor),
                containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ]
            NSLayoutConstraint.activate(constraints)
            return constraints
        }
    }
}
