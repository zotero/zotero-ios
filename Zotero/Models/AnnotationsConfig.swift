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
    static let sidebarWidth: CGFloat = 250
    static let previewSize: CGSize = createPreviewSize()

    static let isZoteroKey = "isZoteroAnnotation"
    static let keyKey = "zoteroKey"

    #if PDFENABLED
    static let supported: PSPDFKit.Annotation.Kind = [.note, .highlight, .square]
    #endif

    private static func createPreviewSize() -> CGSize {
        let scale = UIScreen.main.scale
        let size = sidebarWidth * scale
        return CGSize(width: size, height: size)
    }
}
