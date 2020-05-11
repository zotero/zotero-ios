//
//  PSPDFKit+Extensions.swift
//  Zotero
//
//  Created by Michal Rentka on 06/05/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

#if PDFENABLED

import UIKit

import PSPDFKit

extension Document {
    func annotation(on page: Int, with key: String) -> PSPDFKit.Annotation? {
        return self.annotations(at: UInt(page)).first(where: { $0.key == key })
    }
}

extension PSPDFKit.Annotation {
    var isZoteroAnnotation: Bool {
        return (self.customData?[PDFReaderState.zoteroAnnotationKey] as? Bool) ?? false
    }

    var isSelectionAnnotation: Bool {
        return (self.customData?[PDFReaderState.zoteroSelectionKey] as? Bool) ?? false
    }

    var key: String? {
        return self.customData?[PDFReaderState.zoteroKeyKey] as? String
    }
}

#endif
