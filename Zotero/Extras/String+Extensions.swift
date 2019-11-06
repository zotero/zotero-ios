//
//  String+Mimetype.swift
//  Zotero
//
//  Created by Michal Rentka on 20/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import CoreServices
import CocoaLumberjack

private let stripCharacters = CharacterSet(charactersIn: "\t\r\n")

extension String {
    var extensionFromMimeType: String? {
        guard let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, self as CFString, nil),
              let ext = UTTypeCopyPreferredTagWithClass(uti.takeRetainedValue(), kUTTagClassFilenameExtension) else{
            return nil
        }
        return ext.takeRetainedValue() as String
    }

    var strippedHtml: String? {
        guard !self.isEmpty else { return nil }

        guard let data = self.data(using: .utf8) else {
            DDLogError("Could not create data from string: \(self)")
            return nil
        }

        do {
            let attributed = try NSAttributedString(data: data,
                                                    options: [.documentType : NSAttributedString.DocumentType.html],
                                                    documentAttributes: nil)
            var stripped = attributed.string.trimmingCharacters(in: CharacterSet.whitespaces)
                                            .components(separatedBy: stripCharacters).joined()
            if stripped.count > 200 {
                let endIndex = stripped.index(stripped.startIndex, offsetBy: 200)
                stripped = String(stripped[stripped.startIndex..<endIndex])
            }
            return stripped
        } catch let error {
            DDLogError("Can't strip HTML tags: \(error)\nOriginal string: '\(self)'")
        }

        return nil
    }

    var parsedDate: Date? {
        let dates = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
                                                      .matches(in: self, range: NSRange(location: 0, length: self.count))
                                                      .compactMap({ $0.date })
        return dates?.first
    }
}
