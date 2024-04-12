//
//  ReaderSettingsAction.swift
//  Zotero
//
//  Created by Michal Rentka on 02.03.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import PSPDFKitUI

enum ReaderSettingsAction {
    // PDF only
    case setTransition(PSPDFKitUI.PageTransition)
    case setPageMode(PSPDFKitUI.PageMode)
    case setDirection(PSPDFKitUI.ScrollDirection)
    case setPageFitting(PSPDFKitUI.PDFConfiguration.SpreadFitting)
    case setPageSpreads(isFirstPageAlwaysSingle: Bool)
    // General
    case setAppearance(ReaderSettingsState.Appearance)
    case setIdleTimerDisabled(Bool)
}
