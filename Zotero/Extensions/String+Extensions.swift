//
//  String+Mimetype.swift
//  Zotero
//
//  Created by Michal Rentka on 20/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import CoreServices

extension String {
    var mimeTypeFromExtension: String? {
        if let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, self as NSString, nil)?.takeRetainedValue() {
            if let mimetype = UTTypeCopyPreferredTagWithClass(uti, kUTTagClassMIMEType)?.takeRetainedValue() {
                return mimetype as String
            }
        }
        return nil
    }

    var extensionFromMimeType: String? {
        guard let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, self as CFString, nil),
              let ext = UTTypeCopyPreferredTagWithClass(uti.takeRetainedValue(), kUTTagClassFilenameExtension) else{
            return nil
        }
        return ext.takeRetainedValue() as String
    }
}
