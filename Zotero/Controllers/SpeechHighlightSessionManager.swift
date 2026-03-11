//
//  SpeechHighlightSessionManager.swift
//  Zotero
//
//  Created by Michal Rentka on 11.03.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import NaturalLanguage

enum HighlightVoiceInfo {
    /// Remote voice with known granularity and audio playback progress.
    case remote(granularity: NLTokenUnit, audioProgress: Float, elapsedTime: TimeInterval)
    /// Local voice — progress is estimated from character position within the current sentence.
    case local
}

protocol SpeechHighlightSessionManagerDelegate: AnyObject {
    associatedtype PageIndex: Hashable
    func highlightSessionNextPageData(from pageIndex: PageIndex) -> (pageText: String, pageIndex: PageIndex)?
    func highlightSessionPreviousPageData(from pageIndex: PageIndex) -> (pageText: String, pageIndex: PageIndex)?
}

final class SpeechHighlightSessionManager<Delegate: SpeechHighlightSessionManagerDelegate> {
    typealias PageIndex = Delegate.PageIndex

    struct Session {
        /// Individual unit ranges in document order. The first element is the leftmost unit, the last is the rightmost.
        var unitRanges: [NSRange]
        /// Index into `unitRanges` pointing to the initially selected unit.
        let anchorIndex: Int
        let granularity: NLTokenUnit
        let pageText: String
        let pageIndex: PageIndex

        /// The combined range spanning all unit ranges.
        var range: NSRange {
            guard let first = unitRanges.first, let last = unitRanges.last else { return NSRange() }
            return NSRange(location: first.location, length: last.location + last.length - first.location)
        }
    }

    private(set) var session: Session?
    weak var delegate: Delegate?

    var hasActiveSession: Bool { session != nil }

    /// Starts a new highlight session by finding the appropriate unit at the given speech position.
    /// Uses voice info to determine granularity and a "go back" heuristic (< 50% progress or < 3 seconds elapsed).
    func startSession(
        voiceInfo: HighlightVoiceInfo,
        position: Int,
        pageText: String,
        pageIndex: PageIndex
    ) -> (text: String, pageIndex: PageIndex)? {
        let clampedPosition = min(max(position, 0), max(pageText.count - 1, 0))

        let granularity: NLTokenUnit
        let shouldGoBack: Bool

        switch voiceInfo {
        case .remote(let voiceGranularity, let audioProgress, let elapsedTime):
            granularity = voiceGranularity
            shouldGoBack = audioProgress < 0.5 || elapsedTime < 3.0

        case .local:
            granularity = .sentence
            if let sentence = TextTokenizer.findSentenceContaining(index: clampedPosition, in: pageText), sentence.range.length > 0 {
                let posInSentence = max(0, clampedPosition - sentence.range.location)
                shouldGoBack = Float(posInSentence) / Float(sentence.range.length) < 0.5
            } else {
                shouldGoBack = false
            }
        }

        // Find the current unit containing the speech position
        let currentUnit = findUnitContaining(granularity: granularity, index: clampedPosition, in: pageText)
        guard let currentUnit else { return nil }

        if shouldGoBack {
            // Try previous unit on the same page
            if let prevIdx = TextTokenizer.findIndex(ofPreviousWhole: granularity, beforeIndex: currentUnit.range.location, in: pageText),
               let prev = findUnit(granularity: granularity, startingAt: prevIdx, in: pageText) {
                session = Session(unitRanges: [prev.range], anchorIndex: 0, granularity: granularity, pageText: pageText, pageIndex: pageIndex)
                return (prev.text, pageIndex)
            }
            // Try last unit on the previous page
            if let prevPageData = delegate?.highlightSessionPreviousPageData(from: pageIndex),
               let lastIdx = TextTokenizer.findIndex(ofPreviousWhole: granularity, beforeIndex: prevPageData.pageText.count, in: prevPageData.pageText),
               let last = findUnit(granularity: granularity, startingAt: lastIdx, in: prevPageData.pageText) {
                session = Session(unitRanges: [last.range], anchorIndex: 0, granularity: granularity, pageText: prevPageData.pageText, pageIndex: prevPageData.pageIndex)
                return (last.text, prevPageData.pageIndex)
            }
        }

        // Use the current unit
        session = Session(unitRanges: [currentUnit.range], anchorIndex: 0, granularity: granularity, pageText: pageText, pageIndex: pageIndex)
        return (currentUnit.text, pageIndex)
    }

    /// Moves to the next unit as a single selection. If anchor+1 exists in unitRanges, uses that.
    /// Otherwise finds the next unit after the anchor in the text, crossing to the next page if needed.
    func moveForward() -> (text: String, pageIndex: PageIndex)? {
        guard let session else { return nil }

        if session.anchorIndex + 1 < session.unitRanges.count {
            let newRange = session.unitRanges[session.anchorIndex + 1]
            self.session = Session(unitRanges: [newRange], anchorIndex: 0, granularity: session.granularity, pageText: session.pageText, pageIndex: session.pageIndex)
            return currentResult()
        }

        let anchorRange = session.unitRanges[session.anchorIndex]
        if let next = findNextUnit(granularity: session.granularity, afterEndOf: anchorRange, in: session.pageText) {
            self.session = Session(unitRanges: [next.range], anchorIndex: 0, granularity: session.granularity, pageText: session.pageText, pageIndex: session.pageIndex)
            return currentResult()
        }

        // No next unit on current page — try next page
        if let nextPageData = delegate?.highlightSessionNextPageData(from: session.pageIndex),
           let first = findUnit(granularity: session.granularity, startingAt: 0, in: nextPageData.pageText) {
            self.session = Session(unitRanges: [first.range], anchorIndex: 0, granularity: session.granularity, pageText: nextPageData.pageText, pageIndex: nextPageData.pageIndex)
            return currentResult()
        }

        return nil
    }

    /// Moves to the previous unit as a single selection. If anchor-1 exists in unitRanges, uses that.
    /// Otherwise finds the previous unit before the anchor in the text, crossing to the previous page if needed.
    func moveBackward() -> (text: String, pageIndex: PageIndex)? {
        guard let session else { return nil }

        if session.anchorIndex - 1 >= 0 {
            let newRange = session.unitRanges[session.anchorIndex - 1]
            self.session = Session(unitRanges: [newRange], anchorIndex: 0, granularity: session.granularity, pageText: session.pageText, pageIndex: session.pageIndex)
            return currentResult()
        }

        let anchorRange = session.unitRanges[session.anchorIndex]
        if let prevIdx = TextTokenizer.findIndex(ofPreviousWhole: session.granularity, beforeIndex: anchorRange.location, in: session.pageText),
           let prev = findUnit(granularity: session.granularity, startingAt: prevIdx, in: session.pageText) {
            self.session = Session(unitRanges: [prev.range], anchorIndex: 0, granularity: session.granularity, pageText: session.pageText, pageIndex: session.pageIndex)
            return currentResult()
        }

        // No previous unit on current page — try previous page
        if let prevPageData = delegate?.highlightSessionPreviousPageData(from: session.pageIndex),
           let lastIdx = TextTokenizer.findIndex(ofPreviousWhole: session.granularity, beforeIndex: prevPageData.pageText.count, in: prevPageData.pageText),
           let last = findUnit(granularity: session.granularity, startingAt: lastIdx, in: prevPageData.pageText) {
            self.session = Session(unitRanges: [last.range], anchorIndex: 0, granularity: session.granularity, pageText: prevPageData.pageText, pageIndex: prevPageData.pageIndex)
            return currentResult()
        }

        return nil
    }

    /// Extends highlight forward: if selection was expanded backward beyond the anchor, shrinks from the start first.
    /// Otherwise appends the next unit to the end. Stays on the current page only.
    func extendForward() -> (text: String, pageIndex: PageIndex)? {
        guard var session else { return nil }

        if session.anchorIndex > 0 {
            session.unitRanges.removeFirst()
            self.session = Session(unitRanges: session.unitRanges, anchorIndex: session.anchorIndex - 1, granularity: session.granularity, pageText: session.pageText, pageIndex: session.pageIndex)
            return currentResult()
        }

        let lastRange = session.unitRanges.last!
        guard let next = findNextUnit(granularity: session.granularity, afterEndOf: lastRange, in: session.pageText) else { return nil }

        session.unitRanges.append(next.range)
        self.session = Session(unitRanges: session.unitRanges, anchorIndex: session.anchorIndex, granularity: session.granularity, pageText: session.pageText, pageIndex: session.pageIndex)
        return currentResult()
    }

    /// Extends highlight backward: if selection was expanded forward beyond the anchor, shrinks from the end first.
    /// Otherwise prepends the previous unit to the start. Stays on the current page only.
    func extendBackward() -> (text: String, pageIndex: PageIndex)? {
        guard var session else { return nil }

        if session.anchorIndex < session.unitRanges.count - 1 {
            session.unitRanges.removeLast()
            self.session = Session(unitRanges: session.unitRanges, anchorIndex: session.anchorIndex, granularity: session.granularity, pageText: session.pageText, pageIndex: session.pageIndex)
            return currentResult()
        }

        let firstRange = session.unitRanges.first!
        guard let prevIdx = TextTokenizer.findIndex(ofPreviousWhole: session.granularity, beforeIndex: firstRange.location, in: session.pageText),
              let prev = findUnit(granularity: session.granularity, startingAt: prevIdx, in: session.pageText) else { return nil }

        session.unitRanges.insert(prev.range, at: 0)
        self.session = Session(unitRanges: session.unitRanges, anchorIndex: session.anchorIndex + 1, granularity: session.granularity, pageText: session.pageText, pageIndex: session.pageIndex)
        return currentResult()
    }

    /// Ends the session and returns the final combined text and page index for annotation creation.
    func endSession() -> (text: String, pageIndex: PageIndex)? {
        guard let session else {
            self.session = nil
            return nil
        }
        let text = extractText(from: session.pageText, range: session.range)
        let pageIndex = session.pageIndex
        self.session = nil
        return (text, pageIndex)
    }

    /// Cancels the session without returning text.
    func cancelSession() {
        session = nil
    }

    /// Returns the current combined highlighted text.
    func currentText() -> String? {
        guard let session else { return nil }
        return extractText(from: session.pageText, range: session.range)
    }

    // MARK: - Private

    private func currentResult() -> (text: String, pageIndex: PageIndex)? {
        guard let session, let text = currentText() else { return nil }
        return (text, session.pageIndex)
    }

    private func extractText(from text: String, range: NSRange) -> String {
        let start = text.index(text.startIndex, offsetBy: range.location)
        let end = text.index(start, offsetBy: range.length)
        return String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func findUnitContaining(granularity: NLTokenUnit, index: Int, in text: String) -> (text: String, range: NSRange)? {
        if granularity == .paragraph {
            return TextTokenizer.findParagraphContaining(index: index, in: text)
        } else {
            return TextTokenizer.findSentenceContaining(index: index, in: text)
        }
    }

    private func findNextUnit(granularity: NLTokenUnit, afterEndOf range: NSRange, in text: String) -> (text: String, range: NSRange)? {
        var startIndex = range.location + range.length
        // Skip whitespace/newlines to handle paragraph boundaries (e.g. \n\n between paragraphs)
        while startIndex < text.count {
            let idx = text.index(text.startIndex, offsetBy: startIndex)
            if text[idx].isWhitespace || text[idx].isNewline {
                startIndex += 1
            } else {
                break
            }
        }
        return findUnit(granularity: granularity, startingAt: startIndex, in: text)
    }

    private func findUnit(granularity: NLTokenUnit, startingAt index: Int, in text: String) -> (text: String, range: NSRange)? {
        if granularity == .paragraph {
            return TextTokenizer.findParagraph(startingAt: index, in: text)
        } else {
            return TextTokenizer.findSentence(startingAt: index, in: text)
        }
    }
}
