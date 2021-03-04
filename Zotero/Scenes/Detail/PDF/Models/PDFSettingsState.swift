//
//  PDFSettingsState.swift
//  Zotero
//
//  Created by Michal Rentka on 04.03.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

#if PDFENABLED

import PSPDFKitUI

struct PDFSettingsState {
    let direction: ScrollDirection
    let transition: PageTransition
    let appearanceMode: PDFReaderState.AppearanceMode
}

#endif
