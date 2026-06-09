//
//  Appearance.swift
//  Zotero
//
//  Created by Michal Rentka on 14.02.2025.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

enum Appearance {
    case light
    case dark
    case sepia

    static func from(appearanceMode: ReaderSettingsState.Appearance, interfaceStyle: UIUserInterfaceStyle) -> Appearance {
        switch appearanceMode {
        case .automatic:
            switch interfaceStyle {
            case .dark:
                return .dark

            default:
                return .light
            }

        case .light:
            return .light

        case .dark:
            return .dark

        case .sepia:
            return .sepia
        }
    }

    var htmlEpubValue: String {
        switch self {
        case .dark:
            return "dark"

        case .light, .sepia:
            return "light"
        }
    }

    var htmlEpubTheme: String? {
        switch self {
        case .sepia:
            return "sepia"

        case .light:
            return "light"

        case .dark:
            return "dark"
        }
    }

    var htmlEpubThemeColor: UIColor {
        switch self {
        case .light:
            return .white

        case .dark:
            return UIColor(red: 46 / 255, green: 52 / 255, blue: 64 / 255, alpha: 1)

        case .sepia:
            return UIColor(red: 244 / 255, green: 236 / 255, blue: 216 / 255, alpha: 1)
        }
    }
}
