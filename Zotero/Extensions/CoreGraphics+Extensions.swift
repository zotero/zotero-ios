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

    func distance(to rect: CGRect) -> CGFloat {
        let left = rect.maxX < self.minX
        let right = self.maxX < rect.minX
        let bottom = rect.maxY < self.minY
        let top = self.maxY < rect.minY

        if top && left {
            return self.distance(from: (self.minX, self.maxY), to: (rect.maxX, rect.minY))
        } else if left && bottom {
            return self.distance(from: (self.minX, self.minY), to: (rect.maxX, rect.maxY))
        } else if bottom && right {
            return self.distance(from: (self.maxX, self.minY), to: (rect.minX, rect.maxY))
        } else if right && top {
            return self.distance(from: (self.maxX, self.maxY), to: (rect.minX, rect.minY))
        } else if left {
            return self.minX - rect.maxX
        } else if right {
            return rect.minX - self.maxX
        } else if bottom {
            return self.minY - rect.maxY
        } else if top {
            return rect.minY - self.maxY
        }

        return 0
    }

    private func distance(from fromPoint: (CGFloat, CGFloat), to toPoint: (CGFloat, CGFloat)) -> CGFloat {
        return sqrt(((fromPoint.0 - toPoint.0) * (fromPoint.0 - toPoint.0)) + (fromPoint.1 - toPoint.1) * (fromPoint.1 - toPoint.1))
    }
}

extension CGPoint {
    func rounded(to places: Int) -> CGPoint {
        return CGPoint(x: self.x.rounded(to: places), y: self.y.rounded(to: places))
    }
}
