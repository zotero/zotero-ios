//
//  NotePreviewGenerator.swift
//  Zotero
//
//  Created by Michal Rentka on 14.06.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift

struct NotePreviewGenerator {
    private static let stripCharacters = CharacterSet(charactersIn: "\t")
    private static let htmlExpression = try? NSRegularExpression(pattern: #"<[^>]*>"#)

    /// Creates preview/title for a Note. Strips HTML characters (by using NSAttributedString). Removes any tabs for readability.
    /// Returns only first line from whole string and limits it to 200 characters.
    static func preview(from note: String) -> String? {
        guard !note.isEmpty, var stripped = self.stripHtml(from: note) else { return nil }

        stripped = stripped.replacingOccurrences(of: "\t", with: "")
        stripped = stripped.components(separatedBy: .newlines).first ?? stripped
        stripped = stripped.trimmingCharacters(in: CharacterSet.whitespaces)

        if stripped.count > 200 {
            let endIndex = stripped.index(stripped.startIndex, offsetBy: 200)
            stripped = String(stripped[stripped.startIndex..<endIndex])
        }
        return stripped
    }

    private static func stripHtml(from string: String) -> String? {
        guard let expression = self.htmlExpression else {
            DDLogWarn("NotePreviewGenerator: wrong regular expression!")
            return nil
        }

        var stripped = string
        let matches = expression.matches(in: string, options: [], range: NSRange(string.startIndex..., in: string))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: stripped) else { continue }
            stripped = stripped.replacingCharacters(in: range, with: "")
        }
        return stripped
    }
}
