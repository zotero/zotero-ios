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
    /// NLTokenizer may return overly long "sentences" when periods are followed directly by characters (e.g., footnote numbers).
    static let maxSentenceLength = 350

    /// Regex pattern for sentence-ending punctuation followed by a digit.
    /// Matches: period/exclamation/question followed by digit (common in PDFs with footnote markers like "sentence.5").
    /// Does not match uppercase letters to avoid splitting abbreviations like "U.S."
    private static let sentenceEndPattern = try! NSRegularExpression(pattern: #"[.!?](?=[0-9])"#)

    /// Finds the sentence at the given index, with intelligent splitting for problematic cases.
    /// If the index is in the middle of a sentence, returns from startIndex to the end of that sentence.
    /// Handles cases where NLTokenizer fails to split sentences properly (e.g., "sentence.5 Next" where footnote marker follows period).
    /// Returns the extracted text and its range in the original string.
    static func findSentence(startingAt startIndex: Int, in text: String) -> (text: String, range: NSRange)? {
        guard startIndex < text.count else { return nil }

        let searchStartIndex = text.index(text.startIndex, offsetBy: startIndex)
        let remainingText = String(text[searchStartIndex...])
        let trimmedRemainingText = remainingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRemainingText.isEmpty else { return nil }

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = remainingText

        let tokenRange = tokenizer.tokenRange(at: remainingText.startIndex)
        var extractedText = String(remainingText[tokenRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        var length = remainingText.distance(from: tokenRange.lowerBound, to: tokenRange.upperBound)

        if extractedText.isEmpty {
            // NLTokenizer didn't find a meaningful token (e.g., text without ending punctuation), use trimmed remaining text
            extractedText = trimmedRemainingText
            let trimmedRange = remainingText.range(of: trimmedRemainingText)!
            let location = startIndex + remainingText.distance(from: remainingText.startIndex, to: trimmedRange.lowerBound)
            length = trimmedRemainingText.count

            // Try to find a natural split point or enforce max length
            if let (splitText, splitLength) = findSentenceSplitPoint(in: extractedText) {
                return (splitText, NSRange(location: location, length: splitLength))
            }
            return (extractedText, NSRange(location: location, length: length))
        }

        let location = startIndex + remainingText.distance(from: remainingText.startIndex, to: tokenRange.lowerBound)

        // Try to find a natural split point (e.g., ".5" or ".A" patterns) or enforce max length
        if let (splitText, splitLength) = findSentenceSplitPoint(in: extractedText) {
            return (splitText, NSRange(location: location, length: splitLength))
        }

        return (extractedText, NSRange(location: location, length: length))
    }

    /// Finds a split point in the text, either at a natural sentence boundary that NLTokenizer missed,
    /// or at the maximum length if the text is too long.
    /// Returns nil if no splitting is needed.
    private static func findSentenceSplitPoint(in text: String) -> (text: String, length: Int)? {
        let range = NSRange(text.startIndex..., in: text)

        // Look for natural split points (punctuation followed by digit, e.g., footnote markers)
        if let match = sentenceEndPattern.firstMatch(in: text, range: range) {
            let matchEndLocation = match.range.location + match.range.length
            // Only split if it's not near the end of the text (leave at least a few characters for next sentence)
            if matchEndLocation < text.count - 1 {
                let endIndex = text.index(text.startIndex, offsetBy: matchEndLocation)
                let splitText = String(text[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !splitText.isEmpty {
                    return (splitText, matchEndLocation)
                }
            }
        }

        // If no natural split point and text doesn't exceed max length, no splitting needed
        guard text.count > maxSentenceLength else { return nil }

        // Text exceeds max length - split at the last space before maxLength
        let truncated = String(text.prefix(maxSentenceLength))
        if let lastSpaceIndex = truncated.lastIndex(of: " ") {
            let splitText = String(truncated[..<lastSpaceIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let splitLength = text.distance(from: text.startIndex, to: lastSpaceIndex)
            if !splitText.isEmpty {
                return (splitText, splitLength)
            }
        }

        // Ultimate fallback: just truncate at maxLength
        return (truncated.trimmingCharacters(in: .whitespacesAndNewlines), maxSentenceLength)
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

    /// Finds the start index of the next sentence or paragraph after the current one.
    static func findIndex(ofNext granularity: NLTokenUnit, startingAt startIndex: Int, in text: String) -> Int? {
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
