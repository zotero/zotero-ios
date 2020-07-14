//
//  UIDevice+Extensions.swift
//  Zotero
//
//  Created by Michal Rentka on 14/07/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

extension UIDevice {
    fileprivate static let compactWidthLimit: CGFloat = 414

    /// Decides whether width of given size is "compact". Compact width means it's less or equal than a width of iPhone Max screen in portrait.
    /// - parameter size: Size of current view.
    /// - returns: `true` if view size is compact, `false` otherwise.
    func isCompactWidth(size: CGSize) -> Bool {
        return size.width <= UIDevice.compactWidthLimit
    }
}
