//
//  AnnotationPopoverLayout.swift
//  Zotero
//
//  Created by Michal Rentka on 27.11.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

struct AnnotationPopoverLayout {
    static let width: CGFloat = 400
    static let tagPickerPreferredSize: CGSize = CGSize(width: AnnotationPopoverLayout.width, height: UIScreen.main.bounds.height)
    static let pageEditPreferredSize: CGSize = CGSize(width: AnnotationPopoverLayout.width, height: 200)

    static let annotationLayout = AnnotationViewLayout(type: .popover)
}
