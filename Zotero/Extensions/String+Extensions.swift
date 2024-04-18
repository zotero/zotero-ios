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
        // The `UTType.preferredMIMEType` sometimes crashes in background. For that reason here are some hardoced mostly used values in our app to avoid using code below.

        switch self.lowercased() {
        case "pdf":
            return "application/pdf"

        case "zip":
            return "application/zip"

        case "html", "htm":
            return "text/html"

        case "xhtml":
            return "application/xhtml+xml"

        case "jpg", "jpeg":
            return "image/jpeg"

        case "png":
            return "image/png"

        case "txt":
            return "text/plain"

        case "gif":
            return "image/gif"

        case "css":
            return "text/css"

        case "epub":
            return "application/epub+zip"

        case "js":
            return "text/javascript"

        case "json":
            return "application/json"

        case "xml":
            return "application/xml"

        default: break
        }

        return UTType(tag: self, tagClass: .filenameExtension, conformingTo: nil)?.preferredMIMEType
    }

    var extensionFromMimeType: String? {
        // The `UTType.preferredFilenameExtension` sometimes crashes in background. For that reason here are some hardoced mostly used values in our app to avoid using code below.

        switch self {
        case "application/pdf":
            return "pdf"

        case "application/zip":
            return "zip"

        case "text/html":
            return "html"

        case "application/xhtml+xml":
            return "xhtml"

        case "image/jpeg":
            return "jpg"

        case "image/png":
            return "png"

        case "text/plain":
            return "txt"

        case "image/gif":
            return "gif"

        case "text/css":
            return "css"

        case "application/epub+zip":
            return "epub"

        case "text/javascript":
            return "js"

        case "application/json":
            return "json"

        case "text/xml", "application/xml":
            return "xml"

        default: break
        }

        return UTType(tag: self, tagClass: .mimeType, conformingTo: nil)?.preferredFilenameExtension
    }

    var mimeTypeFromBase64EncodedImageData: String? {
        guard count > 6, let endIndex = firstIndex(of: ";") else { return nil }
        let startIndex = index(startIndex, offsetBy: 5)
        return String(self[startIndex..<endIndex])
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
