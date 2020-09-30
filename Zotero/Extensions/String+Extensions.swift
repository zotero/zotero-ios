//
//  String+Mimetype.swift
//  Zotero
//
//  Created by Michal Rentka on 20/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import CoreServices

import CocoaLumberjackSwift

private let stripCharacters = CharacterSet(charactersIn: "\t")

extension String {
    /// Creates preview/title for a Note. Strips HTML characters (by using NSAttributedString). Removes any tabs for readability.
    /// Returns only first line from whole string and limits it to 200 characters.
    var notePreview: String? {
        guard !self.isEmpty else { return nil }

        guard let data = self.data(using: .utf8) else {
            DDLogError("Could not create data from string: \(self)")
            return nil
        }

        do {
            let attributed = try NSAttributedString(data: data,
                                                    options: [.documentType : NSAttributedString.DocumentType.html,
                                                              .characterEncoding: String.Encoding.utf8.rawValue],
                                                    documentAttributes: nil)
            var stripped = attributed.string.components(separatedBy: stripCharacters).joined()
                                            .trimmingCharacters(in: CharacterSet.whitespaces)
            stripped = stripped.components(separatedBy: .newlines).first ?? stripped
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
}
