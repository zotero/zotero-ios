//
//  AnnotationViewLayout.swift
//  Zotero
//
//  Created by Michal Rentka on 27.11.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

struct AnnotationViewLayout {
    let horizontalInset: CGFloat
    let headerVerticalInsets: CGFloat
    let pageLabelLeadingOffset: CGFloat
    let highlightContentLeadingOffset: CGFloat
    let buttonVerticalInset: CGFloat
    let lineHeight: CGFloat
    let verticalSpacerHeight: CGFloat
    // Line width shown next to the highlighted text in highlight annotation (sidebar or popover).
    let highlightLineWidth: CGFloat
    let highlightLineVerticalInsets: CGFloat
    let commentMinHeight: CGFloat?

    let font: UIFont
    let pageLabelFont: UIFont

    let backgroundColor: UIColor

    let showsContent: Bool
    let scrollableBody: Bool
    let showDoneButton: Bool

    init(type: AnnotationView.Kind) {
        horizontalInset = 16
        pageLabelLeadingOffset = 8
        highlightContentLeadingOffset = 8
        highlightLineWidth = 3
        highlightLineVerticalInsets = 8

        switch type {
        case .cell:
            headerVerticalInsets = 9
            buttonVerticalInset = 9
            lineHeight = 20
            verticalSpacerHeight = 12.5
            font = .preferredFont(forTextStyle: .subheadline)
            pageLabelFont = .preferredFont(for: .subheadline, weight: .bold)
            showsContent = true
            commentMinHeight = nil
            scrollableBody = false
            backgroundColor = .systemBackground
            showDoneButton = false
            
        case .popover:
            headerVerticalInsets = 14
            buttonVerticalInset = 11
            lineHeight = 22
            verticalSpacerHeight = 16
            font = .preferredFont(forTextStyle: .body)
            pageLabelFont = .preferredFont(for: .body, weight: .bold)
            showsContent = false
            commentMinHeight = lineHeight * 3
            scrollableBody = true
            backgroundColor = Asset.Colors.annotationPopoverBackground.color
            showDoneButton = UIDevice.current.userInterfaceIdiom == .phone
        }
    }
}
