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
    static let sidebarWidth: CGFloat = 300
    static let previewSize: CGSize = createPreviewSize()
    static let areaLineWidth: CGFloat = 2
    static let defaultActiveColor = UIColor(hex: "#ff8c19")
    static let colors: [String] = ["#ff6666", "#ff8c19", "#5fb236", "#2ea8e5", "#a28ae5"]

    static let isZoteroKey = "isZoteroAnnotation"
    static let keyKey = "zoteroKey"

    #if PDFENABLED
    static let supported: PSPDFKit.Annotation.Kind = [.note, .highlight, .square]
    #endif

    private static func createPreviewSize() -> CGSize {
        let scale = UIScreen.main.scale
        let size = sidebarWidth * scale
        return CGSize(width: ceil(size), height: ceil(size))
    }
}
