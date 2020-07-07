//
//  TagColorGenerator.swift
//  Zotero
//
//  Created by Michal Rentka on 16/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import SwiftUI

struct TagColorGenerator {
    static func color(for hex: String, scheme: ColorScheme) -> Color {
        if hex.isEmpty {
            return .gray
        }
        return Color(hex: self.hex(for: hex, isDark: (scheme == .dark)))
    }

    static func uiColor(for hex: String, style: UIUserInterfaceStyle) -> UIColor {
        if hex.isEmpty {
            return .gray
        }
        return UIColor(hex: self.hex(for: hex, isDark: (style == .dark)))
    }

    // TODO: - figure out colors for dark mode
    private static func hex(for hex: String, isDark: Bool) -> String {
        if (hex.isEmpty || hex == "#000000") && isDark {
            return "#696969"
        }
        return hex
    }
}
