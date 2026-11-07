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
        return untrimmedOriginalText(from: text, range: range).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extracts substring from original text using an NSRange.
    private static func untrimmedOriginalText(from text: String, range: NSRange) -> String {
        let start = text.index(text.startIndex, offsetBy: range.location)
        let end = text.index(start, offsetBy: range.length)
        return String(text[start..<end])
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

    /// Splits a sentence over `maxSentenceLength`, like `enforceMaxLength(in:)`, given as found in the text (`rawText` may start
    /// and end with whitespace, which the limit doesn't count). The returned length is measured from the start of `rawText`,
    /// leading whitespace included, so that it can be applied from the start of the sentence's range.
    private static func enforceMaxLength(inUntrimmed rawText: String) -> (text: String, length: Int)? {
        guard let (splitText, splitLength) = enforceMaxLength(in: rawText.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        let leadingWhitespaceCount = rawText.prefix(while: { $0.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) }).count
        return (splitText, leadingWhitespaceCount + splitLength)
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
            let rawText = untrimmedOriginalText(from: text, range: originalRange)

            if let (splitText, splitLength) = enforceMaxLength(inUntrimmed: rawText) {
                return (splitText, NSRange(location: originalRange.location, length: splitLength))
            }
            return (rawText.trimmingCharacters(in: .whitespacesAndNewlines), originalRange)
        }

        let normLocation = normStartIndex + remainingNormText.distance(from: remainingNormText.startIndex, to: tokenRange.lowerBound)
        let normLength = remainingNormText.distance(from: tokenRange.lowerBound, to: tokenRange.upperBound)
        let originalRange = normalized.originalRange(from: NSRange(location: normLocation, length: normLength))
        let rawText = untrimmedOriginalText(from: text, range: originalRange)

        if let (splitText, splitLength) = enforceMaxLength(inUntrimmed: rawText) {
            return (splitText, NSRange(location: originalRange.location, length: splitLength))
        }

        return (rawText.trimmingCharacters(in: .whitespacesAndNewlines), originalRange)
    }

    /// Ranges of the sentences of `text`, in order, as successive `findSentence(startingAt:)` calls return them (each starting
    /// where the previous one ended), but normalizing and tokenizing the text once instead of once per sentence.
    /// - parameter tokenizer: Sentence tokenizer to reuse across calls, so that it's set up once.
    static func sentenceRanges(in text: String, tokenizer: NLTokenizer = NLTokenizer(unit: .sentence)) -> [NSRange] {
        let characters = Array(text)
        guard !characters.isEmpty else { return [] }

        let normalized = normalizeText(text)
        let normalizedCharacters = Array(normalized.text)
        tokenizer.string = normalized.text
        // Sentence tokens as `Character` offsets in the normalized text.
        var tokens: [(start: Int, end: Int)] = []
        var lastIndex = normalized.text.startIndex
        var lastOffset = 0
        tokenizer.enumerateTokens(in: normalized.text.startIndex..<normalized.text.endIndex) { range, _ in
            let start = lastOffset + normalized.text.distance(from: lastIndex, to: range.lowerBound)
            let end = start + normalized.text.distance(from: range.lowerBound, to: range.upperBound)
            tokens.append((start, end))
            lastIndex = range.upperBound
            lastOffset = end
            return true
        }

        var ranges: [NSRange] = []
        var index = 0
        var tokenIndex = 0
        while index < characters.count {
            let normalizedStart = normalized.normalizedIndex(for: index)
            guard let firstNonWhitespace = normalizedCharacters[normalizedStart...].firstIndex(where: { !$0.isWhitespace && !$0.isNewline }) else { break }

            // `findSentence(startingAt:)` tokenizes the text from its start index, so the sentence runs from there to the end of
            // the token it falls in.
            while tokenIndex < tokens.count && tokens[tokenIndex].end <= normalizedStart {
                tokenIndex += 1
            }
            let normalizedRange: NSRange
            if tokenIndex < tokens.count,
               tokens[tokenIndex].start <= normalizedStart,
               normalizedCharacters[normalizedStart..<tokens[tokenIndex].end].contains(where: { !$0.isWhitespace && !$0.isNewline }) {
                normalizedRange = NSRange(location: normalizedStart, length: tokens[tokenIndex].end - normalizedStart)
            } else {
                // No meaningful token, the rest of the text is the sentence (see `findSentence(startingAt:)`).
                let lastNonWhitespace = normalizedCharacters.lastIndex(where: { !$0.isWhitespace && !$0.isNewline }) ?? firstNonWhitespace
                normalizedRange = NSRange(location: firstNonWhitespace, length: lastNonWhitespace + 1 - firstNonWhitespace)
            }

            var range = normalized.originalRange(from: normalizedRange)
            if let (_, splitLength) = enforceMaxLength(inUntrimmed: String(characters[range.location..<NSMaxRange(range)])) {
                range = NSRange(location: range.location, length: splitLength)
            }
            let end = NSMaxRange(range)
            guard end > index else { break }
            ranges.append(range)
            index = end
        }
        return ranges
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

    /// Finds the full paragraph containing the given index, from its beginning to its end, even if the index is in the
    /// middle of the paragraph. Returns the extracted text and its range in the original string.
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

    /// Finds the start index of the next sentence after the current one. Footnote-normalized before tokenizing.
    static func nextSentenceStart(after startIndex: Int, in text: String) -> Int? {
        guard startIndex < text.count else { return nil }

        let normalized = normalizeText(text)
        let normStartIndex = normalized.normalizedIndex(for: startIndex)
        guard let normResult = nextSentenceTokenStart(startIndex: normStartIndex, in: normalized.text) else { return nil }
        return normalized.originalIndex(for: normResult)
    }

    /// Tokenizes the full text into sentences and returns the position to start the next reading from:
    /// - If `startIndex` is at or before the start of a token, returns that token's start.
    /// - If `startIndex` is inside a token, returns that token's upperBound (the start of the following token / trailing whitespace).
    /// Tokenizing the full text (rather than a slice starting at `startIndex`) preserves the surrounding context NLTokenizer
    /// needs to detect boundaries.
    private static func nextSentenceTokenStart(startIndex: Int, in text: String) -> Int? {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        var result: Int?
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { tokenRange, _ in
            let tokenText = text[tokenRange]
            guard !tokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }

            let lb = text.distance(from: text.startIndex, to: tokenRange.lowerBound)
            let ub = text.distance(from: text.startIndex, to: tokenRange.upperBound)

            if startIndex <= lb {
                result = lb
                return false
            }
            if startIndex < ub {
                result = ub
                return false
            }
            return true
        }
        return result
    }

    /// Finds the start index of the previous whole sentence before the given position.
    /// If the index is in the middle of a sentence, returns the start of the sentence before that one.
    /// If the index is at the end of a sentence, returns the start of that sentence.
    /// Returns nil if there is no previous whole sentence.
    static func previousSentenceStart(before index: Int, in text: String) -> Int? {
        guard index > 0, index <= text.count else { return nil }

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
}
