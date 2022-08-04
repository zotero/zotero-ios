//
//  ItemDetailLayout.swift
//  Zotero
//
//  Created by Michal Rentka on 03/11/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

struct ItemDetailLayout {
    static let lineHeight: CGFloat = 22
    static let separatorHeight: CGFloat = 1 / UIScreen.main.scale
    static let minCellHeight: CGFloat = 44 - separatorHeight
    static let sectionHeaderHeight: CGFloat = 44
    static let horizontalInset: CGFloat = 16
    static let iconWidth: CGFloat = 28

    static func insets(for section: ItemDetailCollectionViewHandler.Section, isEditing: Bool, isFirstRow: Bool, isLastRow: Bool) -> UIEdgeInsets {
        let top: CGFloat
        let bottom: CGFloat

        switch section {
        case .type:
            if isEditing {
                top = 15
                bottom = 15
            } else {
                top = 20
                bottom = 10
            }
        case .dates:
            if isEditing {
                top = 15
                bottom = 15
            } else {
                top = 10
                bottom = isLastRow ? 20 : 10
            }
        case .tags:
            if isEditing {
                top = isLastRow ? 0 : 15
                bottom = isLastRow ? 0 : 15
            } else {
                top = isFirstRow ? 20 : 10
                bottom = isLastRow ? 20 : 10
            }
        case .creators:
            if isEditing {
                top = isLastRow ? 0 : 15
                bottom = isLastRow ? 0 : 15
            } else {
                top = 10
                bottom = 10
            }
        case .fields:
            top = isEditing ? 15 : 10
            bottom = isEditing ? 15 : 10
        case .abstract:
            top = 15
            bottom = 15
        case .attachments, .notes:
            if isEditing && isLastRow {
                top = 0
                bottom = 0
            } else {
                top = 15
                bottom = 15
            }
        case .title:
            top = 43 + separatorHeight
            bottom = 20 + separatorHeight
        }

        return UIEdgeInsets(top: top/2, left: horizontalInset, bottom: bottom/2, right: horizontalInset)
    }
}
