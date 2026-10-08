//
//  AnnotationPopoverAction.swift
//  Zotero
//
//  Created by Michal Rentka on 30.11.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

enum AnnotationPopoverAction {
    case setColor(String)
    case setLineWidth(CGFloat)
    case setPageLabel(String)
    case setTags([Tag])
    case setComment(NSAttributedString)
    case delete
    case setProperties(type: AnnotationType, pageLabel: String, highlightText: NSAttributedString)
}
