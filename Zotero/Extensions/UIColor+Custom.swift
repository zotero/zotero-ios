//
//  UIColor+Custom.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

extension UIColor {
    convenience init(hex: String, alpha: CGFloat = 1) {
        guard let hex = UIColor.fullHex(from: hex) else {
            self.init(white: 0, alpha: alpha)
            return
        }

        let hexInt = UIColor.intFromHexString(hexStr: hex)
        self.init(red: CGFloat((hexInt >> 16) & 0xff) / 0xff,
                  green: CGFloat((hexInt >> 8) & 0xff) / 0xff,
                  blue: CGFloat(hexInt & 0xff) / 0xff,
                  alpha: alpha)
    }

    private static func intFromHexString(hexStr: String) -> UInt64 {
        var hexInt: UInt64 = 0
        let scanner: Scanner = Scanner(string: hexStr)
        scanner.charactersToBeSkipped = CharacterSet(charactersIn: "#")
        scanner.scanHexInt64(&hexInt)
        return hexInt
    }

    static func fullHex(from hex: String) -> String? {
        let startsWithHashag = hex.starts(with: "#")

        switch hex.count {
        case 4 where startsWithHashag, 3:
            return hex.reduce("") { result, char in
                if char == "#" {
                    return (result ?? "") + "\(char)"
                } else {
                    return (result ?? "") + "\(char)\(char)"
                }
            }
        case 7 where startsWithHashag, 6:
            return hex
        default:
            return nil
        }
    }

    var hexString: String {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0

        getRed(&r, green: &g, blue: &b, alpha: &a)

        let rgb = (Int)(r * 255) << 16 | (Int)(g * 255) << 8 | (Int)(b * 255) << 0
        return String(format: "#%06x", rgb)
    }

    func createImage(size: CGSize) -> UIImage {
        return UIGraphicsImageRenderer(size: size).image { rendererContext in
            self.setFill()
            rendererContext.fill(CGRect(origin: .zero, size: size))
        }
    }
}
