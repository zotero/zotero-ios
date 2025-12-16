//
//  AnnotationToolsSettingsState.swift
//  Zotero
//
//  Created by Michal Rentka on 12.12.2025.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

struct AnnotationToolsSettingsState: ViewModelState {
    enum Section: Int {
        case pdf
        case htmlEpub
    }

    var pdfTools: [AnnotationToolButton]
    var htmlEpubTools: [AnnotationToolButton]

    init(pdfAnnotationTools: [AnnotationToolButton], htmlEpubAnnotationTools: [AnnotationToolButton]) {
        pdfTools = pdfAnnotationTools
        htmlEpubTools = htmlEpubAnnotationTools
    }

    mutating func cleanup() {
    }
}
