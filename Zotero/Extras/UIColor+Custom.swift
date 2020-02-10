//
//  UIColor+Custom.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

extension UIColor {
    static var redButton: UIColor {
        return .red
    }

    convenience init(hex: String) {
        let hexInt = UIColor.intFromHexString(hexStr: hex)
        self.init(red: CGFloat((hexInt >> 16) & 0xff) / 0xff,
                  green: CGFloat((hexInt >> 8) & 0xff) / 0xff,
                  blue: CGFloat(hexInt & 0xff) / 0xff,
                  alpha: 1)
    }

    private static func intFromHexString(hexStr: String) -> UInt64 {
        var hexInt: UInt64 = 0
        let scanner: Scanner = Scanner(string: hexStr)
        scanner.charactersToBeSkipped = CharacterSet(charactersIn: "#")
        scanner.scanHexInt64(&hexInt)
        return hexInt
    }
}
