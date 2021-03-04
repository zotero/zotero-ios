//
//  PDFSettingsAction.swift
//  Zotero
//
//  Created by Michal Rentka on 04.03.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

#if PDFENABLED

import PSPDFKitUI

enum PDFSettingsAction {
    case changeDirection(ScrollDirection)
    case changeTransition(PageTransition)
    case changeAppearanceMode(PDFReaderState.AppearanceMode)
}

#endif
