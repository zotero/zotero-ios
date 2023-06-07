//
//  PDFSettingsAction.swift
//  Zotero
//
//  Created by Michal Rentka on 02.03.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import PSPDFKitUI

enum PDFSettingsAction {
    case setTransition(PageTransition)
    case setPageMode(PageMode)
    case setDirection(ScrollDirection)
    case setPageFitting(PDFConfiguration.SpreadFitting)
    case setAppearanceMode(PDFReaderState.AppearanceMode)
    case setIdleTimerDisabled(Bool)
}
