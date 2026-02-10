//
//  TextTokenizer.swift
//  Zotero
//
//  Created by Michal Rentka on 2025.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import NaturalLanguage

enum TextTokenizer {
    /// Finds the token (sentence or paragraph) at the given index.
    /// Returns the extracted text and its range in the original string.
    static func find(_ granularity: NLTokenUnit, startingAt startIndex: Int, in text: String) -> (text: String, range: NSRange)? {
        guard startIndex < text.count else { return nil }

        let searchStartIndex = text.index(text.startIndex, offsetBy: startIndex)
        let remainingText = String(text[searchStartIndex...])
        let trimmedRemainingText = remainingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRemainingText.isEmpty else { return nil }

        let tokenizer = NLTokenizer(unit: granularity)
        tokenizer.string = remainingText

        let tokenRange = tokenizer.tokenRange(at: remainingText.startIndex)
        let extractedText = String(remainingText[tokenRange]).trimmingCharacters(in: .whitespacesAndNewlines)

        if !extractedText.isEmpty {
            let location = startIndex + remainingText.distance(from: remainingText.startIndex, to: tokenRange.lowerBound)
            let length = remainingText.distance(from: tokenRange.lowerBound, to: tokenRange.upperBound)
            return (extractedText, NSRange(location: location, length: length))
        }

        // NLTokenizer didn't find a meaningful token (e.g., text without ending punctuation), return the entire trimmed remaining text
        let trimmedRange = remainingText.range(of: trimmedRemainingText)!
        let location = startIndex + remainingText.distance(from: remainingText.startIndex, to: trimmedRange.lowerBound)
        let length = trimmedRemainingText.count
        return (trimmedRemainingText, NSRange(location: location, length: length))
    }

    /// Finds the start index of the previous whole token (sentence or paragraph) before the given position.
    /// If the index is in the middle of a token, returns the start of the token before that one.
    /// If the index is at the end of a token, returns the start of that token.
    /// Returns nil if there is no previous whole token.
    static func findIndex(ofPreviousWhole granularity: NLTokenUnit, beforeIndex index: Int, in text: String) -> Int? {
        guard index > 0, index <= text.count else { return nil }
        
        let tokenizer = NLTokenizer(unit: granularity)
        tokenizer.string = text
        
        // Collect only non-whitespace tokens
        var tokens: [Range<String.Index>] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { tokenRange, _ in
            let tokenText = text[tokenRange]
            if !tokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                tokens.append(tokenRange)
            }
            return true
        }
        
        guard !tokens.isEmpty else { return nil }
        
        let indexPosition = text.index(text.startIndex, offsetBy: index)
        
        // Find which token contains or precedes our index
        var targetTokenIndex: Int?
        for (i, tokenRange) in tokens.enumerated() {
            if indexPosition <= tokenRange.lowerBound {
                // Index is before or at the start of this token, so previous whole token is i-1
                targetTokenIndex = i - 1
                break
            } else if indexPosition < tokenRange.upperBound {
                // Index is in the middle of this token, so previous whole token is i-1
                targetTokenIndex = i - 1
                break
            } else if indexPosition == tokenRange.upperBound {
                // Index is at the end of this token, so this token (i) is the previous whole token
                targetTokenIndex = i
                break
            }
        }
        
        // If we didn't find a position, index is after all tokens - return last token
        if targetTokenIndex == nil {
            targetTokenIndex = tokens.count - 1
        }
        
        guard let idx = targetTokenIndex, idx >= 0 else { return nil }
        
        return text.distance(from: text.startIndex, to: tokens[idx].lowerBound)
    }
}
