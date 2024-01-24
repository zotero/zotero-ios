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
    var idleTimerDisabled: Bool

    init(settings: PDFSettings) {
        self.transition = settings.transition
        self.pageMode = settings.pageMode
        self.scrollDirection = settings.direction
        self.pageFitting = settings.pageFitting
        self.appearance = settings.appearanceMode
        self.idleTimerDisabled = settings.idleTimerDisabled
    }

    init(settings: HtmlEpubSettings) {
        self.appearance = settings.appearance
        self.idleTimerDisabled = settings.idleTimerDisabled
        // These don't apply to HTML/Epub, assign random values
        self.transition = .curl
        self.pageMode = .automatic
        self.scrollDirection = .horizontal
        self.pageFitting = .adaptive
    }

    func cleanup() {}
}
