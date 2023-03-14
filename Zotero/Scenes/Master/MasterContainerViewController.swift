//
//  MasterContainerViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 08.03.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class MasterContainerViewController: UIViewController {
    let upperController: UIViewController
    let bottomController: UIViewController

    init(topController: UIViewController, bottomController: UIViewController) {
        self.upperController = topController
        self.bottomController = bottomController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.upperController.view.translatesAutoresizingMaskIntoConstraints = false
        self.bottomController.view.translatesAutoresizingMaskIntoConstraints = false

        self.upperController.willMove(toParent: self)
        self.view.addSubview(self.upperController.view)
        self.addChild(self.upperController)
        self.upperController.didMove(toParent: self)

        self.bottomController.willMove(toParent: self)
        self.view.addSubview(self.bottomController.view)
        self.addChild(self.bottomController)
        self.bottomController.didMove(toParent: self)

        let hairline = UIView()
        hairline.translatesAutoresizingMaskIntoConstraints = false
        hairline.backgroundColor = .separator
        self.view.addSubview(hairline)

        NSLayoutConstraint.activate([
            self.view.topAnchor.constraint(equalTo: self.upperController.view.topAnchor),
            self.view.bottomAnchor.constraint(equalTo: self.bottomController.view.bottomAnchor),
            self.view.leadingAnchor.constraint(equalTo: self.upperController.view.leadingAnchor),
            self.view.leadingAnchor.constraint(equalTo: self.bottomController.view.leadingAnchor),
            self.view.trailingAnchor.constraint(equalTo: self.upperController.view.trailingAnchor),
            self.view.trailingAnchor.constraint(equalTo: self.bottomController.view.trailingAnchor),
            self.upperController.view.bottomAnchor.constraint(equalTo: self.bottomController.view.topAnchor),
            self.upperController.view.heightAnchor.constraint(equalTo: self.bottomController.view.heightAnchor, multiplier: 2),
            hairline.heightAnchor.constraint(equalToConstant: 1/UIScreen.main.scale),
            hairline.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            hairline.topAnchor.constraint(equalTo: self.upperController.view.bottomAnchor)
        ])
    }
}
