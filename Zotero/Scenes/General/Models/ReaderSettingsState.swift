//
//  ReaderSettingsState.swift
//  Zotero
//
//  Created by Michal Rentka on 01.03.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import PSPDFKitUI

struct ReaderSettingsState: ViewModelState {
    enum Appearance: UInt {
        case light
        case dark
        case automatic

        var userInterfaceStyle: UIUserInterfaceStyle {
            switch self {
            case .automatic: return .unspecified
            case .dark: return .dark
            case .light: return .light
            }
        }
    }

    var transition: PSPDFKitUI.PageTransition
    var pageMode: PSPDFKitUI.PageMode
    var scrollDirection: PSPDFKitUI.ScrollDirection
    var pageFitting: PSPDFKitUI.PDFConfiguration.SpreadFitting
    var appearance: ReaderSettingsState.Appearance
    var isFirstPageAlwaysSingle: Bool

    init(settings: PDFSettings) {
        transition = settings.transition
        pageMode = settings.pageMode
        scrollDirection = settings.direction
        pageFitting = settings.pageFitting
        appearance = settings.appearanceMode
        isFirstPageAlwaysSingle = settings.isFirstPageAlwaysSingle
    }

    func cleanup() {}
}
