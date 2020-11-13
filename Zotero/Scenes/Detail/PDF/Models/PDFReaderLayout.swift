//
//  PDFReaderLayout.swift
//  Zotero
//
//  Created by Michal Rentka on 11/11/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

struct PDFReaderLayout {
    static let sidebarWidth: CGFloat = createSidebarWidth()
    static let separatorWidth: CGFloat = 1 / UIScreen.main.scale
    static let imageAnnotationLineWidth: CGFloat = 2
    static let noteSize: CGSize = CGSize(width: 32, height: 32)
    static let horizontalInset: CGFloat = 16
    static let annotationHeaderHeight: CGFloat = 36
    static let annotationHeaderPageLeadingOffset: CGFloat = 8
    static let annotationHighlightContentLeadingOffset: CGFloat = 8
    static let annotationLineHeight: CGFloat = 20
    static let annotationVerticalSpacerHeight: CGFloat = 12.5

    static let font: UIFont = .systemFont(ofSize: 15)
    static let pageLabelFont: UIFont = .systemFont(ofSize: 15, weight: .bold)

    private static func createSidebarWidth() -> CGFloat {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return 320
        }
        return UIScreen.main.bounds.width
    }
}
