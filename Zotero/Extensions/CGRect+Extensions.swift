//
//  CGRect+Extensions.swift
//  Zotero
//
//  Created by Michal Rentka on 26/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

extension CGRect {
    var heightToWidthRatio: CGFloat {
        return self.height / self.width
    }

    var widthToHeightRatio: CGFloat {
        return self.width / self.height
    }

    func rounded(to places: Int) -> CGRect {
        return CGRect(x: self.minX.rounded(to: places), y: self.minY.rounded(to: places), width: self.width.rounded(to: places), height: self.height.rounded(to: places))
    }
}
