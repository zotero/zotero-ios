//
//  AnnotationsConfig.swift
//  Zotero
//
//  Created by Michal Rentka on 12/05/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

#if PDFENABLED
import PSPDFKit
#endif

struct AnnotationsConfig {
    static let defaultActiveColor = "#ffd400"
    static let colors: [String] = ["#ffd400", "#ff6666", "#5fb236", "#2ea8e5", "#a28ae5"]

    static let keyKey = "ZOTERO:Key"
    static let baseColorKey = "ZOTERO:BaseColor"
    static let syncableKey = "ZOTERO:Syncable"

    // Line width of image annotation in PDF document.
    static let imageAnnotationLineWidth: CGFloat = 2
    // Size of note annotation in PDF document.
    static let noteAnnotationSize: CGSize = CGSize(width: 22, height: 22)

    #if PDFENABLED
    static let supported: PSPDFKit.Annotation.Kind = [.note, .highlight, .square]
    #endif
}
