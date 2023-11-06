//
//  UIView+Extensions.swift
//  Zotero
//
//  Created by Michal Rentka on 19/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

extension UIView {
    static var nibName: String {
        return String(describing: self)
    }

    @objc override var scene: UIScene? {
        if let window {
            window.windowScene
        } else {
            next?.scene
        }
    }
}
