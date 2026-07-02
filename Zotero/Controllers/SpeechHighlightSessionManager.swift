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
    /// Paragraph segments (text + page-text offset) for the page, in reading order. Empty if the page has no readable content.
    func highlightSessionSegments(forPage pageIndex: PageIndex) -> [SpeechDocumentParser.Segment]
    /// The next readable page (one that has segments), or nil.
    func highlightSessionNextReadablePage(after pageIndex: PageIndex) -> PageIndex?
    /// The previous readable page (one that has segments), or nil.
    func highlightSessionPreviousReadablePage(before pageIndex: PageIndex) -> PageIndex?
}

final class SpeechHighlightSessionManager<Delegate: SpeechHighlightSessionManagerDelegate> {
    typealias PageIndex = Delegate.PageIndex
    typealias Segment = SpeechDocumentParser.Segment

    struct Session {
        /// Individual unit ranges (page-text offsets) in document order. The first element is the leftmost unit, the last is the rightmost.
        var unitRanges: [NSRange]
        /// Index into `unitRanges` pointing to the initially selected unit.
        let anchorIndex: Int
        let granularity: NLTokenUnit
        /// The page's paragraph segments (source of truth for units); the page text is derived from them.
        let segments: [Segment]
        let pageIndex: PageIndex

        /// The combined range spanning all unit ranges.
        var range: NSRange {
            guard let first = unitRanges.first, let last = unitRanges.last else { return NSRange() }
            return NSRange(location: first.location, length: last.location + last.length - first.location)
        }

        /// The page's readable text, derived by joining the segments (used to extract highlighted text and as the hint denominator).
        var pageText: String {
            return segments.map(\.text).joined(separator: SpeechDocumentParser.segmentSeparator)
        }
    }

    private static var inactivityTimeout: TimeInterval { 5 }

    private(set) var session: Session? {
        didSet {
            if session != nil {
                startInactivityTimer()
            } else {
                stopInactivityTimer()
            }
        }
    }
    private var inactivityTimer: Timer?
    weak var delegate: Delegate?
    var annotationTool: AnnotationTool = .highlight
    var annotationColor: String = AnnotationsConfig.defaultActiveColor
    var onSessionTimedOut: (() -> Void)?

    var hasActiveSession: Bool { session != nil }

    func startInactivityTimer() {
        inactivityTimer?.invalidate()
        inactivityTimer = Timer.scheduledTimer(withTimeInterval: Self.inactivityTimeout, repeats: false) { [weak self] _ in
            self?.onSessionTimedOut?()
        }
    }

    func stopInactivityTimer() {
        inactivityTimer?.invalidate()
        inactivityTimer = nil
    }

    /// Starts a new highlight session by finding the appropriate unit at the given speech position (a page-text offset).
    /// Uses voice info to determine granularity and a "go back" heuristic (< 50% progress or < 3 seconds elapsed).
    func startSession(
        voiceInfo: HighlightVoiceInfo,
        position: Int,
        segments: [Segment],
        pageIndex: PageIndex
    ) -> (text: String, pageIndex: PageIndex)? {
        let clampedPosition = min(max(position, 0), max(pageTextLength(of: segments) - 1, 0))

        let granularity: NLTokenUnit
        let shouldGoBack: Bool

        switch voiceInfo {
        case .remote(let voiceGranularity, let audioProgress, let elapsedTime):
            granularity = voiceGranularity
            // If less than 50% and less than 3 seconds into the current segment, use the previous one
            shouldGoBack = audioProgress < 0.5 && elapsedTime < 3.0

        case .local:
            granularity = .sentence
            if let sentence = SpeechDocumentParser.unitRange(containing: clampedPosition, granularity: .sentence, in: segments), sentence.length > 0 {
                let posInSentence = max(0, clampedPosition - sentence.location)
                shouldGoBack = Float(posInSentence) / Float(sentence.length) < 0.5
            } else {
                shouldGoBack = false
            }
        }

        // Find the current unit containing the speech position
        guard let currentUnit = SpeechDocumentParser.unitRange(containing: clampedPosition, granularity: granularity, in: segments) else { return nil }

        if shouldGoBack {
            // Try previous unit on the same page
            if let prev = SpeechDocumentParser.previousUnitRange(before: currentUnit.location, granularity: granularity, in: segments) {
                return setSession(unitRanges: [prev], anchorIndex: 0, granularity: granularity, segments: segments, pageIndex: pageIndex)
            }
            // Try last unit on the previous page
            if let prevIndex = delegate?.highlightSessionPreviousReadablePage(before: pageIndex) {
                let prevSegments = delegate?.highlightSessionSegments(forPage: prevIndex) ?? []
                if let last = SpeechDocumentParser.lastUnitRange(granularity: granularity, in: prevSegments) {
                    return setSession(unitRanges: [last], anchorIndex: 0, granularity: granularity, segments: prevSegments, pageIndex: prevIndex)
                }
            }
        }

        // Use the current unit
        return setSession(unitRanges: [currentUnit], anchorIndex: 0, granularity: granularity, segments: segments, pageIndex: pageIndex)
    }

    /// Moves to the next unit as a single selection. If anchor+1 exists in unitRanges, uses that.
    /// Otherwise finds the next unit after the anchor, crossing to the next page if needed.
    func moveForward() -> (text: String, pageIndex: PageIndex)? {
        guard let session else { return nil }

        if session.anchorIndex + 1 < session.unitRanges.count {
            return setSession(unitRanges: [session.unitRanges[session.anchorIndex + 1]], anchorIndex: 0, granularity: session.granularity, segments: session.segments, pageIndex: session.pageIndex)
        }

        let anchorRange = session.unitRanges[session.anchorIndex]
        if let next = SpeechDocumentParser.nextUnitRange(afterEndOf: anchorRange, granularity: session.granularity, in: session.segments) {
            return setSession(unitRanges: [next], anchorIndex: 0, granularity: session.granularity, segments: session.segments, pageIndex: session.pageIndex)
        }

        // No next unit on current page — try next page
        if let nextIndex = delegate?.highlightSessionNextReadablePage(after: session.pageIndex) {
            let nextSegments = delegate?.highlightSessionSegments(forPage: nextIndex) ?? []
            if let first = SpeechDocumentParser.firstUnitRange(granularity: session.granularity, in: nextSegments) {
                return setSession(unitRanges: [first], anchorIndex: 0, granularity: session.granularity, segments: nextSegments, pageIndex: nextIndex)
            }
        }

        return nil
    }

    /// Moves to the previous unit as a single selection. If anchor-1 exists in unitRanges, uses that.
    /// Otherwise finds the previous unit before the anchor, crossing to the previous page if needed.
    func moveBackward() -> (text: String, pageIndex: PageIndex)? {
        guard let session else { return nil }

        if session.anchorIndex - 1 >= 0 {
            return setSession(unitRanges: [session.unitRanges[session.anchorIndex - 1]], anchorIndex: 0, granularity: session.granularity, segments: session.segments, pageIndex: session.pageIndex)
        }

        let anchorRange = session.unitRanges[session.anchorIndex]
        if let prev = SpeechDocumentParser.previousUnitRange(before: anchorRange.location, granularity: session.granularity, in: session.segments) {
            return setSession(unitRanges: [prev], anchorIndex: 0, granularity: session.granularity, segments: session.segments, pageIndex: session.pageIndex)
        }

        // No previous unit on current page — try previous page
        if let prevIndex = delegate?.highlightSessionPreviousReadablePage(before: session.pageIndex) {
            let prevSegments = delegate?.highlightSessionSegments(forPage: prevIndex) ?? []
            if let last = SpeechDocumentParser.lastUnitRange(granularity: session.granularity, in: prevSegments) {
                return setSession(unitRanges: [last], anchorIndex: 0, granularity: session.granularity, segments: prevSegments, pageIndex: prevIndex)
            }
        }

        return nil
    }

    /// Extends highlight forward: if selection was expanded backward beyond the anchor, shrinks from the start first.
    /// Otherwise appends the next unit to the end. Stays on the current page only.
    func extendForward() -> (text: String, pageIndex: PageIndex)? {
        guard var session else { return nil }

        if session.anchorIndex > 0 {
            session.unitRanges.removeFirst()
            return setSession(unitRanges: session.unitRanges, anchorIndex: session.anchorIndex - 1, granularity: session.granularity, segments: session.segments, pageIndex: session.pageIndex)
        }

        let lastRange = session.unitRanges.last!
        guard let next = SpeechDocumentParser.nextUnitRange(afterEndOf: lastRange, granularity: session.granularity, in: session.segments) else { return nil }

        session.unitRanges.append(next)
        return setSession(unitRanges: session.unitRanges, anchorIndex: session.anchorIndex, granularity: session.granularity, segments: session.segments, pageIndex: session.pageIndex)
    }

    /// Extends highlight backward: if selection was expanded forward beyond the anchor, shrinks from the end first.
    /// Otherwise prepends the previous unit to the start. Stays on the current page only.
    func extendBackward() -> (text: String, pageIndex: PageIndex)? {
        guard var session else { return nil }

        if session.anchorIndex < session.unitRanges.count - 1 {
            session.unitRanges.removeLast()
            return setSession(unitRanges: session.unitRanges, anchorIndex: session.anchorIndex, granularity: session.granularity, segments: session.segments, pageIndex: session.pageIndex)
        }

        let firstRange = session.unitRanges.first!
        guard let prev = SpeechDocumentParser.previousUnitRange(before: firstRange.location, granularity: session.granularity, in: session.segments) else { return nil }

        session.unitRanges.insert(prev, at: 0)
        return setSession(unitRanges: session.unitRanges, anchorIndex: session.anchorIndex + 1, granularity: session.granularity, segments: session.segments, pageIndex: session.pageIndex)
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

    /// Sets the session and returns the current combined text + page index (or nil if the text is empty).
    private func setSession(unitRanges: [NSRange], anchorIndex: Int, granularity: NLTokenUnit, segments: [Segment], pageIndex: PageIndex) -> (text: String, pageIndex: PageIndex)? {
        session = Session(unitRanges: unitRanges, anchorIndex: anchorIndex, granularity: granularity, segments: segments, pageIndex: pageIndex)
        return currentResult()
    }

    private func currentResult() -> (text: String, pageIndex: PageIndex)? {
        guard let session, let text = currentText() else { return nil }
        return (text, session.pageIndex)
    }

    private func extractText(from text: String, range: NSRange) -> String {
        guard range.location >= 0, range.length >= 0, range.location + range.length <= text.count else { return "" }
        let start = text.index(text.startIndex, offsetBy: range.location)
        let end = text.index(start, offsetBy: range.length)
        return String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func pageTextLength(of segments: [Segment]) -> Int {
        guard let last = segments.last else { return 0 }
        return last.pageOffset + last.text.count
    }
}
