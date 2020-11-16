//
//  PDFReaderLayout.swift
//  Zotero
//
//  Created by Michal Rentka on 11/11/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

struct PDFReaderLayout {
    // Sidebar
    static let sidebarWidth: CGFloat = createSidebarWidth()
    static let separatorWidth: CGFloat = 1 / UIScreen.main.scale
    // Document annotations
    // Line width of image annotation in PDF document.
    static let imageAnnotationLineWidth: CGFloat = 2
    // Size of note annotation in PDF document.
    static let noteAnnotationSize: CGSize = CGSize(width: 32, height: 32)
    // Annotation views
    static let annotationsHorizontalInset: CGFloat = 16
    static let annotationsCellSeparatorHeight: CGFloat = 13
    static let annotationHeaderHeight: CGFloat = 36
    static let annotationHeaderPageLeadingOffset: CGFloat = 8
    static let annotationHighlightContentLeadingOffset: CGFloat = 8
    static let annotationLineHeight: CGFloat = 20
    static let annotationVerticalSpacerHeight: CGFloat = 12.5
    static let annotationSelectionLineWidth: CGFloat = 3
    // Line width shown next to the highlighted text in highlight annotation (sidebar or popover).
    static let annotationHighlightLineWidth: CGFloat = 3

    static let font: UIFont = .systemFont(ofSize: 15)
    static let pageLabelFont: UIFont = .systemFont(ofSize: 15, weight: .bold)

    private static func createSidebarWidth() -> CGFloat {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return 320
        }
        return UIScreen.main.bounds.width
    }
}
