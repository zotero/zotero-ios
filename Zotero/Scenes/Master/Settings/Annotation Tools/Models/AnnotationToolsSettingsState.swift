//
//  AnnotationToolsSettingsState.swift
//  Zotero
//
//  Created by Michal Rentka on 12.12.2025.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import OrderedCollections

struct AnnotationToolsSettingsState: ViewModelState {
    enum Section: Int {
        case pdf
        case htmlEpub
    }

    var pdfTools: OrderedDictionary<AnnotationTool, Bool>
    var htmlEpubTools: OrderedDictionary<AnnotationTool, Bool>

    init(pdfAnnotationTools: [AnnotationTool], htmlEpubAnnotationTools: [AnnotationTool]) {
        var pdfTools: OrderedDictionary<AnnotationTool, Bool> = [:]
        pdfAnnotationTools.forEach({ pdfTools[$0] = true })
        ([.eraser, .freeText, .highlight, .image, .ink, .note, .underline] as [AnnotationTool])
            .filter({ !pdfAnnotationTools.contains($0) })
            .forEach({ pdfTools[$0] = false })
        self.pdfTools = pdfTools
        
        var htmlEpubTools: OrderedDictionary<AnnotationTool, Bool> = [:]
        htmlEpubAnnotationTools.forEach({ htmlEpubTools[$0] = true })
        ([.highlight, .underline, .note] as [AnnotationTool])
            .filter({ !htmlEpubAnnotationTools.contains($0) })
            .forEach({ htmlEpubTools[$0] = false })
        self.htmlEpubTools = htmlEpubTools
    }

    mutating func cleanup() {
    }
}
