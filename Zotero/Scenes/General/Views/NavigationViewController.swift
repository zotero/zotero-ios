//
//  NavigationViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 08.12.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class NavigationViewController: UINavigationController {
    var dismissHandler: (() -> Void)?
    var statusBarVisible: Bool = true

    override var prefersStatusBarHidden: Bool {
        return !self.statusBarVisible
    }

    deinit {
        self.dismissHandler?()
    }
}
