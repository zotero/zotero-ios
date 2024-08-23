//
//  AnnotationEditAction.swift
//  Zotero
//
//  Created by Michal Rentka on 30.11.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

enum AnnotationEditAction {
    case setColor(String)
    case setLineWidth(CGFloat)
    case setPageLabel(String, Bool)
    case setHighlight(NSAttributedString)
    case setFontSize(CGFloat)
}
