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
    enum Style {
        case filled
        case border
    }

    static func color(for hex: String, scheme: ColorScheme) -> (color: Color, style: Style) {
        if hex.isEmpty || hex == "#000000" {
            return (.gray, .border)
        }
        let opacity = Double(self.alpha(for: hex, isDarkMode: (scheme == .dark)))
        return (Color(hex: hex).opacity(opacity), .filled)
    }

    static func uiColor(for hex: String) -> (color: UIColor, style: Style) {
        if hex.isEmpty || hex == "#000000" {
            return (.gray, .border)
        }
        let color = UIColor { traitCollection -> UIColor in
            let alpha = self.alpha(for: hex, isDarkMode: (traitCollection.userInterfaceStyle == .dark))
            return UIColor(hex: hex, alpha: alpha)
        }
        return (color, .filled)
    }

    private static func alpha(for hex: String, isDarkMode: Bool) -> CGFloat {
        if !isDarkMode || hex.isEmpty {
            return 1
        }

        switch hex {
        case "#ff6666", "#ff8c19":
            return 0.75
        case "#a28ae5", "#2ea8e5", "#5fb236":
            return 0.8
        case "#009980", "#999999":
            return 0.9
        case "#a6507b", "#576dd9", "#000000":
            return 1.0
        default:
            return 0.8
        }
    }
}
