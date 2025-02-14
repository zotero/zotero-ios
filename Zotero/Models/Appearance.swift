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
}
