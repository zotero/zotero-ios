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
    /// Creates preview/title for a Note. Strips HTML characters (by using NSAttributedString). Removes any tabs for readability.
    /// Returns only first line from whole string and limits it to 200 characters.
    static func preview(from note: String) -> String? {
        guard !note.isEmpty else { return nil }
        
        var stripped = note.strippedHtmlTags.basicUnescape
        stripped = stripped.replacingOccurrences(of: "\t", with: "")
        stripped = stripped.trimmingCharacters(in: .newlines)
        stripped = stripped.components(separatedBy: .newlines).first ?? stripped
        stripped = stripped.trimmingCharacters(in: .whitespaces)

        if stripped.count > 200 {
            let endIndex = stripped.index(stripped.startIndex, offsetBy: 200)
            stripped = String(stripped[stripped.startIndex..<endIndex])
        }
        return stripped
    }
}
