//
//  String+Mimetype.swift
//  Zotero
//
//  Created by Michal Rentka on 20/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import CoreServices
import UniformTypeIdentifiers

extension String {
    var mimeTypeFromExtension: String? {
        UTType(tag: self, tagClass: .filenameExtension, conformingTo: nil)?.preferredMIMEType
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

        return UTType(tag: self, tagClass: .mimeType, conformingTo: nil)?.preferredFilenameExtension
    }

    var strippedHtmlTags: String {
        guard !self.isEmpty else { return self }
        return self.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression, range: nil)
    }

    var strippedRichTextTags: String {
        guard !self.isEmpty else { return self }
        return self.replacingOccurrences(of: #"<\/?[b|i|span|sub|sup][^>]*>"#, with: "", options: .regularExpression, range: nil)
    }

    var basicUnescape: String {
        let characters = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&apos;": "'"
        ]
        var str = self
        for (escaped, unescaped) in characters {
            str = str.replacingOccurrences(of: escaped, with: unescaped, options: NSString.CompareOptions.literal, range: nil)
        }
        return str
    }
}
