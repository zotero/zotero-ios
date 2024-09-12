//
//  CGFloat+Extensions.swift
//  Zotero
//
//  Created by Michal Rentka on 26/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

extension Double {
    func rounded(to places: Int) -> Double {
        guard self.isFinite else { return self }
        return (Decimal(self).rounded(to: places) as NSNumber).doubleValue
    }
}

extension CGFloat {
    func rounded(to places: Int) -> CGFloat {
        guard self.isFinite else { return self }
        return CGFloat((Decimal(self).rounded(to: places) as NSNumber).doubleValue)
    }
}

extension Float {
    func rounded(to places: Int) -> Float {
        guard self.isFinite else { return self }
        return (Decimal(Double(self)).rounded(to: places) as NSNumber).floatValue
    }
}

extension Decimal {
    func rounded(to places: Int, mode: NSDecimalNumber.RoundingMode = .bankers) -> Decimal {
        guard self.isFinite else { return Decimal(0) }

        // TODO: Remove Objective-C bridging when issue is fixed
        // https://forums.developer.apple.com/forums/thread/762711
        // https://developer.apple.com/documentation/xcode-release-notes/xcode-16-release-notes#Foundation
//        var original = self
//        var result: Decimal = 0
//        NSDecimalRound(&result, &original, places, mode)
//        return result
        return NSDecimalNumber.roundedDecimal(self, toPlaces: places, mode: mode)
    }
}
