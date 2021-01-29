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
        return self.annotations(at: UInt(page)).first(where: { $0.key == key || $0.uuid == key })
    }
}

extension PSPDFKit.Annotation {
    /// Defines annotations which are synced with internal DB and Zotero server
    var syncable: Bool {
        get {
            return (self.customData?[AnnotationsConfig.syncableKey] as? Bool) ?? false
        }

        set {
            if self.customData == nil {
                self.customData = [AnnotationsConfig.syncableKey: newValue]
            } else {
                self.customData?[AnnotationsConfig.syncableKey] = newValue
            }
        }
    }

    /// Defines internal Zotero key. PDFs which were previously exported by Zotero may include this flag.
    var key: String? {
        get {
            return self.customData?[AnnotationsConfig.keyKey] as? String
        }

        set {
            if self.customData == nil {
                if let key = newValue {
                    self.customData = [AnnotationsConfig.keyKey: key]
                }
            } else {
                self.customData?[AnnotationsConfig.keyKey] = newValue
            }
        }
    }

    /// Defines base color for given annotation. Current color is derived from base color and may differ in light/dark mode.
    var baseColor: String {
        get {
            return (self.customData?[AnnotationsConfig.baseColorKey] as? String) ?? AnnotationsConfig.defaultActiveColor
        }

        set {
            if self.customData == nil {
                self.customData = [AnnotationsConfig.baseColorKey: newValue]
            } else {
                self.customData?[AnnotationsConfig.baseColorKey] = newValue
            }
        }
    }

    var previewBoundingBox: CGRect {
        return self.boundingBox.insetBy(dx: (self.lineWidth + 1), dy: (self.lineWidth + 1))
    }
}

extension PSPDFKit.SquareAnnotation {
    var isImageAnnotation: Bool {
        return self.key != nil || (self.name ?? "").contains("Zotero")
    }
}

#endif
