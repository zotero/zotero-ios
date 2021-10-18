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
    let headerHeight: CGFloat
    let pageLabelLeadingOffset: CGFloat
    let highlightContentLeadingOffset: CGFloat
    let buttonHeight: CGFloat
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
        self.horizontalInset = 16
        self.pageLabelLeadingOffset = 8
        self.highlightContentLeadingOffset = 8
        self.highlightLineWidth = 3
        self.highlightLineVerticalInsets = 8

        switch type {
        case .cell:
            self.headerHeight = 36
            self.buttonHeight = 36
            self.lineHeight = 20
            self.verticalSpacerHeight = 12.5
            self.font = .systemFont(ofSize: 15)
            self.pageLabelFont = .systemFont(ofSize: 15, weight: .bold)
            self.showsContent = true
            self.commentMinHeight = nil
            self.scrollableBody = false
            self.backgroundColor = .white
            self.showDoneButton = false
            
        case .popover:
            self.headerHeight = 50
            self.buttonHeight = 44
            self.lineHeight = 22
            self.verticalSpacerHeight = 16
            self.font = .preferredFont(forTextStyle: .body)
            self.pageLabelFont = .preferredFont(for: .body, weight: .bold)
            self.showsContent = false
            self.commentMinHeight = self.lineHeight * 3
            self.scrollableBody = true
            self.backgroundColor = Asset.Colors.annotationPopoverBackground.color
            self.showDoneButton = UIDevice.current.userInterfaceIdiom == .phone
        }
    }
}
