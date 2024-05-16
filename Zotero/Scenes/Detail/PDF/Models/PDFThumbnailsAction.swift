//
//  PDFThumbnailsAction.swift
//  Zotero
//
//  Created by Michal Rentka on 04.12.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum PDFThumbnailsAction {
    case prefetch([UInt])
    case load(UInt)
    case setUserInterface(isDark: Bool)
    case loadPages
    case setSelectedPage(pageIndex: Int, type: PDFThumbnailsState.SelectionType)
    case reloadThumbnails
}
