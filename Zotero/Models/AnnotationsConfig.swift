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
    static let colorNames: [String: String] = ["#ffd400": "yellow", "#ff6666": "red", "#5fb236": "green", "#2ea8e5": "blue", "#a28ae5": "purple"]

    static let keyKey = "Zotero:Key"
    static let baseColorKey = "Zotero:BaseColor"

    // Line width of image annotation in PDF document.
    static let imageAnnotationLineWidth: CGFloat = 2
    // Size of note annotation in PDF document.
    static let noteAnnotationSize: CGSize = CGSize(width: 22, height: 22)

    static let positionSizeLimit = 65000

    #if PDFENABLED
    static let supported: PSPDFKit.Annotation.Kind = [.note, .highlight, .square, .ink]
    #endif
}
