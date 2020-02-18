//
//  Color+Extension.swift
//  Zotero
//
//  Created by Michal Rentka on 16/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

extension Color {
    init(hex: String) {
        let hexInt = Color.intFromHexString(hexStr: hex)
        self.init(red: Double((hexInt >> 16) & 0xff) / 0xff,
                  green: Double((hexInt >> 8) & 0xff) / 0xff,
                  blue: Double(hexInt & 0xff) / 0xff)
    }

    private static func intFromHexString(hexStr: String) -> UInt64 {
        var hexInt: UInt64 = 0
        let scanner: Scanner = Scanner(string: hexStr)
        scanner.charactersToBeSkipped = CharacterSet(charactersIn: "#")
        scanner.scanHexInt64(&hexInt)
        return hexInt
    }
}
