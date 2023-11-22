//
//  EmojiExtractor.swift
//  Zotero
//
//  Created by Michal Rentka on 22.11.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct EmojiExtractor {
    static func extractFirstContiguousGroup(from text: String) -> String? {
        var startIndex: Int?
        var endIndex: Int?

        for (idx, character) in text.enumerated() {
            let isEmoji = character.unicodeScalars.first?.properties.isEmoji ?? false
            if startIndex == nil && isEmoji {
                startIndex = idx
            }
            if startIndex != nil && !isEmoji {
                endIndex = idx
                break
            }
        }

        if startIndex != nil && endIndex == nil {
            endIndex = text.count
        }

        guard let startIndex, let endIndex else { return nil }
        return String(text[text.index(text.startIndex, offsetBy: startIndex)..<text.index(text.startIndex, offsetBy: endIndex)])
    }
}
