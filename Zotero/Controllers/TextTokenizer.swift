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
    /// Maximum length for a sentence before forcing a split.
    static let maxSentenceLength = 350

    // MARK: - NormalizedText

    /// Tracks text with removed footnote digits, providing bidirectional index mapping.
    private struct NormalizedText {
        let text: String
        /// Each entry records a removal: `origStart` is the position of the first removed digit in original text, `length` is the number of removed characters.
        let removals: [(origStart: Int, length: Int)]

        func normalizedIndex(for originalIndex: Int) -> Int {
            var offset = 0
            for removal in removals {
                if removal.origStart + removal.length <= originalIndex {
                    offset += removal.length
                } else if removal.origStart <= originalIndex {
                    // Index falls inside a removal - map to position right after the punctuation in normalized text
                    return removal.origStart - offset
                } else {
                    break
                }
            }
            return originalIndex - offset
        }

        func originalIndex(for normalizedIndex: Int) -> Int {
            var cumulativeOffset = 0
            for removal in removals {
                let normPosition = removal.origStart - cumulativeOffset
                if normalizedIndex < normPosition {
                    break
                }
                cumulativeOffset += removal.length
            }
            return normalizedIndex + cumulativeOffset
        }

        func originalRange(from normalizedRange: NSRange) -> NSRange {
            let origStart = originalIndex(for: normalizedRange.location)
            let origEnd = originalIndex(for: normalizedRange.location + normalizedRange.length)
            return NSRange(location: origStart, length: origEnd - origStart)
        }
    }

    // MARK: - Normalization

    /// Removes footnote digits that follow sentence-ending punctuation.
    /// Pattern: `[letter/quote/bracket][.!?][digit+]` → remove all consecutive digits after punctuation.
    /// Does not match decimals like "3.5" (digit before punctuation fails the check).
    private static func normalizeText(_ text: String) -> NormalizedText {
        let chars = Array(text)
        guard chars.count >= 3 else { return NormalizedText(text: text, removals: []) }

        var result = ""
        result.reserveCapacity(chars.count)
        var removals: [(origStart: Int, length: Int)] = []

        var i = 0
        while i < chars.count {
            if ".!?".contains(chars[i]),
               i > 0,
               i + 1 < chars.count,
               isLetterOrQuoteOrBracket(chars[i - 1]),
               chars[i + 1].isNumber {
                // Append the punctuation
                result.append(chars[i])
                i += 1
                // Skip all consecutive digits
                let digitStart = i
                while i < chars.count, chars[i].isNumber {
                    i += 1
                }
                removals.append((origStart: digitStart, length: i - digitStart))
            } else {
                result.append(chars[i])
                i += 1
            }
        }

        return NormalizedText(text: result, removals: removals)
    }

    private static func isLetterOrQuoteOrBracket(_ char: Character) -> Bool {
        char.isLetter || char == "\"" || char == "'" || char == "\u{201D}" || char == "\u{2019}" || char == "]" || char == ")"
    }

    // MARK: - Helpers

    /// Extracts substring from original text using an NSRange, then trims whitespace.
    private static func extractOriginalText(from text: String, range: NSRange) -> String {
        let start = text.index(text.startIndex, offsetBy: range.location)
        let end = text.index(start, offsetBy: range.length)
        return String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Splits text at the last space before `maxSentenceLength` if it exceeds the limit.
    private static func enforceMaxLength(in text: String) -> (text: String, length: Int)? {
        guard text.count > maxSentenceLength else { return nil }

        let truncated = String(text.prefix(maxSentenceLength))
        if let lastSpaceIndex = truncated.lastIndex(of: " ") {
            let splitText = String(truncated[..<lastSpaceIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let splitLength = truncated.distance(from: truncated.startIndex, to: lastSpaceIndex)
            if !splitText.isEmpty {
                return (splitText, splitLength)
            }
        }

        return (truncated.trimmingCharacters(in: .whitespacesAndNewlines), maxSentenceLength)
    }

    // MARK: - Sentence Methods

    /// Finds the sentence at the given index, with pre-processing normalization for footnote boundaries.
    /// If the index is in the middle of a sentence, returns from startIndex to the end of that sentence.
    /// Returns the extracted text and its range in the original string.
    static func findSentence(startingAt startIndex: Int, in text: String) -> (text: String, range: NSRange)? {
        guard startIndex < text.count else { return nil }

        let normalized = normalizeText(text)
        let normStartIndex = normalized.normalizedIndex(for: startIndex)

        let normSearchStart = normalized.text.index(normalized.text.startIndex, offsetBy: normStartIndex)
        let remainingNormText = String(normalized.text[normSearchStart...])
        let trimmedRemaining = remainingNormText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRemaining.isEmpty else { return nil }

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = remainingNormText

        let tokenRange = tokenizer.tokenRange(at: remainingNormText.startIndex)
        let extractedNormText = String(remainingNormText[tokenRange]).trimmingCharacters(in: .whitespacesAndNewlines)

        if extractedNormText.isEmpty {
            // NLTokenizer didn't find a meaningful token, use trimmed remaining text
            let trimmedRange = remainingNormText.range(of: trimmedRemaining)!
            let normLocation = normStartIndex + remainingNormText.distance(from: remainingNormText.startIndex, to: trimmedRange.lowerBound)
            let normLength = trimmedRemaining.count
            let originalRange = normalized.originalRange(from: NSRange(location: normLocation, length: normLength))
            let resultText = extractOriginalText(from: text, range: originalRange)

            if let (splitText, splitLength) = enforceMaxLength(in: resultText) {
                return (splitText, NSRange(location: originalRange.location, length: splitLength))
            }
            return (resultText, originalRange)
        }

        let normLocation = normStartIndex + remainingNormText.distance(from: remainingNormText.startIndex, to: tokenRange.lowerBound)
        let normLength = remainingNormText.distance(from: tokenRange.lowerBound, to: tokenRange.upperBound)
        let originalRange = normalized.originalRange(from: NSRange(location: normLocation, length: normLength))
        let resultText = extractOriginalText(from: text, range: originalRange)

        if let (splitText, splitLength) = enforceMaxLength(in: resultText) {
            return (splitText, NSRange(location: originalRange.location, length: splitLength))
        }

        return (resultText, originalRange)
    }

    /// Finds the paragraph at the given index.
    /// If the index is in the middle of a paragraph, returns from startIndex to the end of that paragraph.
    /// Returns the extracted text and its range in the original string.
    static func findParagraph(startingAt startIndex: Int, in text: String) -> (text: String, range: NSRange)? {
        guard startIndex < text.count else { return nil }

        let searchStartIndex = text.index(text.startIndex, offsetBy: startIndex)
        let remainingText = String(text[searchStartIndex...])
        let trimmedRemainingText = remainingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRemainingText.isEmpty else { return nil }

        let tokenizer = NLTokenizer(unit: .paragraph)
        tokenizer.string = remainingText

        let tokenRange = tokenizer.tokenRange(at: remainingText.startIndex)
        let extractedText = String(remainingText[tokenRange]).trimmingCharacters(in: .whitespacesAndNewlines)

        if !extractedText.isEmpty {
            let location = startIndex + remainingText.distance(from: remainingText.startIndex, to: tokenRange.lowerBound)
            let length = remainingText.distance(from: tokenRange.lowerBound, to: tokenRange.upperBound)
            return (extractedText, NSRange(location: location, length: length))
        }

        // NLTokenizer didn't find a meaningful token, return the entire trimmed remaining text
        let trimmedRange = remainingText.range(of: trimmedRemainingText)!
        let location = startIndex + remainingText.distance(from: remainingText.startIndex, to: trimmedRange.lowerBound)
        let length = trimmedRemainingText.count
        return (trimmedRemainingText, NSRange(location: location, length: length))
    }

    /// Finds the full sentence containing the given index.
    /// Unlike `findSentence(startingAt:)`, this returns the entire sentence from its beginning to its end,
    /// even if the index is in the middle of the sentence.
    /// Returns the extracted text and its range in the original string.
    static func findSentenceContaining(index: Int, in text: String) -> (text: String, range: NSRange)? {
        guard index >= 0, index < text.count else { return nil }

        let normalized = normalizeText(text)
        let normIndex = normalized.normalizedIndex(for: index)

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = normalized.text

        let indexPosition = normalized.text.index(normalized.text.startIndex, offsetBy: normIndex)
        let tokenRange = tokenizer.tokenRange(at: indexPosition)

        let normLocation = normalized.text.distance(from: normalized.text.startIndex, to: tokenRange.lowerBound)
        let normLength = normalized.text.distance(from: tokenRange.lowerBound, to: tokenRange.upperBound)
        let originalRange = normalized.originalRange(from: NSRange(location: normLocation, length: normLength))
        let resultText = extractOriginalText(from: text, range: originalRange)

        guard !resultText.isEmpty else { return nil }

        return (resultText, originalRange)
    }

    /// Finds the full paragraph containing the given index.
    /// Unlike `findParagraph(startingAt:)`, this returns the entire paragraph from its beginning to its end,
    /// even if the index is in the middle of the paragraph.
    /// Returns the extracted text and its range in the original string.
    static func findParagraphContaining(index: Int, in text: String) -> (text: String, range: NSRange)? {
        guard index < text.count else { return nil }

        let tokenizer = NLTokenizer(unit: .paragraph)
        tokenizer.string = text

        let indexPosition = text.index(text.startIndex, offsetBy: index)
        let tokenRange = tokenizer.tokenRange(at: indexPosition)
        let extractedText = String(text[tokenRange]).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !extractedText.isEmpty else { return nil }

        let location = text.distance(from: text.startIndex, to: tokenRange.lowerBound)
        let length = text.distance(from: tokenRange.lowerBound, to: tokenRange.upperBound)
        return (extractedText, NSRange(location: location, length: length))
    }

    /// Finds the start index of the next sentence or paragraph after the current one.
    static func findIndex(ofNext granularity: NLTokenUnit, startingAt startIndex: Int, in text: String) -> Int? {
        guard startIndex < text.count else { return nil }

        if granularity == .sentence {
            let normalized = normalizeText(text)
            let normStartIndex = normalized.normalizedIndex(for: startIndex)

            let searchStart = normalized.text.index(normalized.text.startIndex, offsetBy: normStartIndex)
            let remainingNormText = String(normalized.text[searchStart...])
            let trimmed = remainingNormText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }

            let tokenizer = NLTokenizer(unit: .sentence)
            tokenizer.string = remainingNormText

            let tokenRange = tokenizer.tokenRange(at: remainingNormText.startIndex)
            let extractedText = String(remainingNormText[tokenRange]).trimmingCharacters(in: .whitespacesAndNewlines)

            guard !extractedText.isEmpty else { return nil }

            let normUpperBound = normStartIndex + remainingNormText.distance(from: remainingNormText.startIndex, to: tokenRange.upperBound)
            return normalized.originalIndex(for: normUpperBound)
        }

        // Paragraph path — unchanged
        let searchStartIndex = text.index(text.startIndex, offsetBy: startIndex)
        let remainingText = String(text[searchStartIndex...])
        let trimmedRemainingText = remainingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRemainingText.isEmpty else { return nil }

        let tokenizer = NLTokenizer(unit: granularity)
        tokenizer.string = remainingText

        let tokenRange = tokenizer.tokenRange(at: remainingText.startIndex)
        let extractedText = String(remainingText[tokenRange]).trimmingCharacters(in: .whitespacesAndNewlines)

        if !extractedText.isEmpty {
            return startIndex + remainingText.distance(from: remainingText.startIndex, to: tokenRange.upperBound)
        }

        return nil
    }

    /// Finds the start index of the previous whole token (sentence or paragraph) before the given position.
    /// If the index is in the middle of a token, returns the start of the token before that one.
    /// If the index is at the end of a token, returns the start of that token.
    /// Returns nil if there is no previous whole token.
    static func findIndex(ofPreviousWhole granularity: NLTokenUnit, beforeIndex index: Int, in text: String) -> Int? {
        guard index > 0, index <= text.count else { return nil }

        if granularity == .sentence {
            let normalized = normalizeText(text)
            let normIndex = normalized.normalizedIndex(for: index)

            let tokenizer = NLTokenizer(unit: .sentence)
            tokenizer.string = normalized.text

            var tokens: [Range<String.Index>] = []
            tokenizer.enumerateTokens(in: normalized.text.startIndex..<normalized.text.endIndex) { tokenRange, _ in
                let tokenText = normalized.text[tokenRange]
                if !tokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    tokens.append(tokenRange)
                }
                return true
            }

            guard !tokens.isEmpty else { return nil }

            let indexPosition = normalized.text.index(normalized.text.startIndex, offsetBy: normIndex)

            var targetTokenIndex: Int?
            for (i, tokenRange) in tokens.enumerated() {
                if indexPosition <= tokenRange.lowerBound {
                    targetTokenIndex = i - 1
                    break
                } else if indexPosition < tokenRange.upperBound {
                    targetTokenIndex = i - 1
                    break
                } else if indexPosition == tokenRange.upperBound {
                    targetTokenIndex = i
                    break
                }
            }

            if targetTokenIndex == nil {
                targetTokenIndex = tokens.count - 1
            }

            guard let idx = targetTokenIndex, idx >= 0 else { return nil }

            let normLowerBound = normalized.text.distance(from: normalized.text.startIndex, to: tokens[idx].lowerBound)
            return normalized.originalIndex(for: normLowerBound)
        }

        // Paragraph path — unchanged
        let tokenizer = NLTokenizer(unit: granularity)
        tokenizer.string = text

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

        var targetTokenIndex: Int?
        for (i, tokenRange) in tokens.enumerated() {
            if indexPosition <= tokenRange.lowerBound {
                targetTokenIndex = i - 1
                break
            } else if indexPosition < tokenRange.upperBound {
                targetTokenIndex = i - 1
                break
            } else if indexPosition == tokenRange.upperBound {
                targetTokenIndex = i
                break
            }
        }

        if targetTokenIndex == nil {
            targetTokenIndex = tokens.count - 1
        }

        guard let idx = targetTokenIndex, idx >= 0 else { return nil }

        return text.distance(from: text.startIndex, to: tokens[idx].lowerBound)
    }
}
