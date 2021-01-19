//
//  ContainerViewController.swift
//  ZShare
//
//  Created by Michal Rentka on 18.01.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class ContainerViewController: UIViewController {
    @IBOutlet private weak var containerView: UIView!
    @IBOutlet private weak var containerHeight: NSLayoutConstraint!

    private var didAppear = false

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = .clear
        self.containerView.layer.cornerRadius = 8
        self.containerView.layer.masksToBounds = true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.didAppear = true
    }

    override func preferredContentSizeDidChange(forChildContentContainer container: UIContentContainer) {
        super.preferredContentSizeDidChange(forChildContentContainer: container)
        self.containerHeight.constant = container.preferredContentSize.height

        guard self.didAppear else { return }

        UIView.animate(withDuration: 0.2) {
            self.view.layoutIfNeeded()
        }
    }
}
