//
//  CGFloat+Extensions.swift
//  Zotero
//
//  Created by Michal Rentka on 26/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

extension Double {
    func roundedDecimal(to places: Int) -> Decimal {
        var original = Decimal(self)
        var result: Decimal = 0
        NSDecimalRound(&result, &original, places, .bankers)
        return result
    }

    func rounded(to places: Int) -> Double {
        return (self.roundedDecimal(to: places) as NSNumber).doubleValue
    }
}

extension CGFloat {
    func roundedDecimal(to places: Int) -> Decimal {
        var original = Decimal(self)
        var result: Decimal = 0
        NSDecimalRound(&result, &original, places, .bankers)
        return result
    }

    func rounded(to places: Int) -> CGFloat {
        return CGFloat((self.roundedDecimal(to: places) as NSNumber).doubleValue)
    }
}

extension Float {
    func roundedDecimal(to places: Int) -> Decimal {
        var original = Decimal(Double(self))
        var result: Decimal = 0
        NSDecimalRound(&result, &original, places, .bankers)
        return result
    }

    func rounded(to places: Int) -> Float {
        return (self.roundedDecimal(to: places) as NSNumber).floatValue
    }
}
