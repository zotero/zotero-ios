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
    var isZotero: Bool {
        get {
            return (self.customData?[AnnotationsConfig.isZoteroKey] as? Bool) ?? false
        }

        set {
            if self.customData == nil {
                self.customData = [AnnotationsConfig.isZoteroKey: newValue]
            } else {
                self.customData?[AnnotationsConfig.isZoteroKey] = newValue
            }
        }
    }

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
}

#endif
