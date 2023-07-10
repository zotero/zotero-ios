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
        // The `UTTypeCopyPreferredTagWithClass` sometimes crashes in background. For that reason here are some hardoced mostly used values in our app to avoid using code below.

        switch self {
        case "application/pdf":
            return "pdf"
        case "application/zip":
            return "zip"
        case "text/html":
            return "html"
        case "image/jpeg":
            return "jpg"
        case "text/plain":
            return "txt"
        default: break
        }

        guard let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, self as CFString, nil),
              let ext = UTTypeCopyPreferredTagWithClass(uti.takeRetainedValue(), kUTTagClassFilenameExtension)
        else { return nil }
        return ext.takeRetainedValue() as String
    }

    var strippedHtmlTags: String {
        guard !self.isEmpty else { return self }
        return self.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression, range: nil)
    }
}
