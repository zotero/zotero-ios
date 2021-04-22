//
//  PopoverNavigationViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 22.04.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class PopoverNavigationViewController: UIViewController {
    let childNavigationController: UINavigationController

    init() {
        self.childNavigationController = UINavigationController()
        super.init(nibName: nil, bundle: nil)
    }

    init(rootViewController: UIViewController) {
        self.childNavigationController = UINavigationController(rootViewController: rootViewController)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.setupNavigationController()
    }

    // MARK: - Setups

    private func setupNavigationController() {
        self.childNavigationController.willMove(toParent: self)
        self.addChild(self.childNavigationController)
        self.childNavigationController.view.frame = self.view.bounds
        self.view.addSubview(self.childNavigationController.view)
        self.childNavigationController.didMove(toParent: self)
    }
}
