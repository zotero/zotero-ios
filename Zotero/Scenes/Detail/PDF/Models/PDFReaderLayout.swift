//
//  PDFReaderLayout.swift
//  Zotero
//
//  Created by Michal Rentka on 11/11/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

#if PDFENABLED

import UIKit

struct PDFReaderLayout {
    // Sidebar
    static let sidebarWidth: CGFloat = createSidebarWidth()
    static let separatorWidth: CGFloat = 1 / UIScreen.main.scale
    static let cellSeparatorHeight: CGFloat = 13
    static let cellSelectionLineWidth: CGFloat = 3
    static let searchBarVerticalInset: CGFloat = 16

    private static func createSidebarWidth() -> CGFloat {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return 320
        }
        return UIScreen.main.bounds.width
    }

    // Annotation
    static let annotationLayout = AnnotationViewLayout(type: .cell)
}

#endif
