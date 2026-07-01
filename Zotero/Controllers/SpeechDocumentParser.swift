//
//  SpeechDocumentParser.swift
//  Zotero
//
//  Created by Michal Rentka on 2025.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import NaturalLanguage

/// Turns a materialized `SDTPack` document into per-page read-aloud text.
///
/// Only readable blocks (`paragraph` and `list`) are kept; headings, images, math, preformatted blocks and anything
/// flagged `excluded` (page numbers, running headers/footers, …) are dropped. Each readable block is split by the page
/// its runs belong to (a paragraph can span a page boundary), so that the resulting per-page text matches the text
/// PSPDFKit renders on that page and can be highlighted there. Within a page, segments are separated by a blank line
/// so that downstream sentence/paragraph tokenization treats them as distinct paragraphs.
enum SpeechDocumentParser {
    /// Read-aloud text for a single document page.
    struct ParsedPage {
        /// Concatenated text of all readable segments on the page, separated by blank lines.
        let text: String
        /// Character-offset ranges (within `text`) of the individual paragraph segments, in reading order.
        /// Used for paragraph-granularity navigation so that paragraphs don't have to be re-detected heuristically.
        let paragraphRanges: [NSRange]
    }

    private static let blockTypesToRead: Set<String> = ["paragraph", "list"]
    private static let segmentSeparator = "\n\n"

    /// Parses the `materialize()` output of an `SDTPack` into per-(SDT)page read-aloud text keyed by page index.
    static func parse(materialized: [String: Any]) -> [Int: ParsedPage] {
        guard let content = materialized["content"] as? [[String: Any]] else { return [:] }

        var buffers: [Int: String] = [:]
        var ranges: [Int: [NSRange]] = [:]

        for block in content {
            guard let type = block["type"] as? String, blockTypesToRead.contains(type) else { continue }
            if let flowClass = block["flowClass"] as? String, flowClass == "excluded" { continue }

            let fallbackPage = startPage(of: block) ?? buffers.keys.max() ?? 0
            var runs: [(text: String, page: Int)] = []
            collectRuns(in: block, fallbackPage: fallbackPage, into: &runs)
            appendSegments(from: runs, into: &buffers, ranges: &ranges)
        }

        var result: [Int: ParsedPage] = [:]
        for (page, text) in buffers {
            result[page] = ParsedPage(text: text, paragraphRanges: ranges[page] ?? [])
        }
        return result
    }

    /// Returns the document language (a BCP-47 tag such as `en-GB`) from the structured document text metadata, or nil
    /// if it isn't present. PDFs store it under `Language`, EPUBs under `language`, in `metadata.source.properties`.
    static func language(from materialized: [String: Any]) -> String? {
        guard let metadata = materialized["metadata"] as? [String: Any],
              let source = metadata["source"] as? [String: Any],
              let properties = source["properties"] as? [String: Any] else { return nil }
        let language = (properties["language"] ?? properties["Language"]) as? String
        let trimmed = language?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }

    /// Recursively gathers the leaf text runs of a block, assigning each run the page it is rendered on. Pure-spacing
    /// runs (and any run without its own `textMap`) inherit the page of the surrounding content.
    private static func collectRuns(in node: [String: Any], fallbackPage: Int, into runs: inout [(text: String, page: Int)]) {
        if let text = node["text"] as? String {
            guard !text.isEmpty else { return }
            let page = textMapPage(of: node) ?? runs.last?.page ?? fallbackPage
            runs.append((text, page))
            return
        }

        let nodePage = startPage(of: node) ?? fallbackPage
        guard let children = node["content"] as? [[String: Any]] else { return }
        for child in children {
            collectRuns(in: child, fallbackPage: nodePage, into: &runs)
        }
    }

    /// Groups consecutive runs by page into segments and appends each segment to its page buffer, recording the
    /// segment's character range. A page change inside a block starts a new segment (and thus a new paragraph unit).
    private static func appendSegments(from runs: [(text: String, page: Int)], into buffers: inout [Int: String], ranges: inout [Int: [NSRange]]) {
        var currentPage: Int?
        var segment = ""

        for run in runs {
            if let currentPage, currentPage != run.page {
                flush(page: currentPage, text: segment)
                segment = ""
            }
            currentPage = run.page
            segment += run.text
        }
        if let currentPage {
            flush(page: currentPage, text: segment)
        }

        func flush(page: Int, text: String) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            var buffer = buffers[page] ?? ""
            if !buffer.isEmpty {
                buffer += segmentSeparator
            }
            let location = buffer.count
            buffer += trimmed
            buffers[page] = buffer
            ranges[page, default: []].append(NSRange(location: location, length: trimmed.count))
        }
    }

    /// Returns the page index of a block from its `anchor.pageRects` (the first rect's first element).
    private static func startPage(of node: [String: Any]) -> Int? {
        guard let anchor = node["anchor"] as? [String: Any],
              let pageRects = anchor["pageRects"] as? [[Any]],
              let firstRect = pageRects.first,
              let page = firstRect.first else { return nil }
        return intValue(page)
    }

    /// Returns the page index of a run from its `anchor.textMap` (a JSON string of `[kind, page, x0, y0, x1, y1, …]`
    /// entries, one per line). The page is the second element of the first entry.
    private static func textMapPage(of node: [String: Any]) -> Int? {
        guard let anchor = node["anchor"] as? [String: Any],
              let textMap = anchor["textMap"] as? String,
              let data = textMap.data(using: .utf8),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[Any]],
              let firstEntry = entries.first,
              firstEntry.count > 1 else { return nil }
        return intValue(firstEntry[1])
    }

    private static func intValue(_ value: Any) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }
}

// MARK: - Segment queries

/// Navigation over the paragraph segments produced by the parser. Sentences are detected with `TextTokenizer` but always
/// bounded to a single paragraph segment, so a sentence never spans a paragraph boundary. Shared by `SpeechManager`
/// (forward/backward navigation) and `RemoteVoiceProcessor` (playback segmentation) so both segment identically.
///
/// All indices are character offsets within the page text, matching the ranges the parser produces and `TextTokenizer`.
extension SpeechDocumentParser {
    /// Returns the range from `index` to the end of the paragraph segment that covers it (or the whole next segment
    /// when `index` falls in the gap between segments). Returns nil when `index` is past the last segment.
    static func paragraphSegment(startingAt index: Int, in paragraphRanges: [NSRange]) -> NSRange? {
        for range in paragraphRanges {
            let end = range.location + range.length
            guard index < end else { continue }
            let start = max(index, range.location)
            return NSRange(location: start, length: end - start)
        }
        return nil
    }

    /// Returns the next sentence range starting at `index`, bounded to the paragraph segment that contains it. Returns
    /// nil when `index` is past the last segment.
    static func sentenceSegment(startingAt index: Int, in text: String, paragraphRanges: [NSRange]) -> NSRange? {
        guard let paragraph = paragraphSegment(startingAt: index, in: paragraphRanges) else { return nil }
        guard let sentence = TextTokenizer.findSentence(startingAt: paragraph.location, in: text) else { return nil }
        let paragraphEnd = paragraph.location + paragraph.length
        let sentenceEnd = min(sentence.range.location + sentence.range.length, paragraphEnd)
        let length = sentenceEnd - sentence.range.location
        guard length > 0 else { return nil }
        return NSRange(location: sentence.range.location, length: length)
    }

    /// Returns the start index of the sentence that follows the one containing `index`, bounded to paragraph segments.
    /// When `index` is inside the last sentence of its segment, returns the first sentence start of the next segment.
    /// Returns nil when there is no following sentence within `paragraphRanges`. Unlike `sentenceSegment`, this advances
    /// past the sentence containing `index` (used for forward navigation, where `index` may be mid-sentence).
    static func nextSentenceStart(after index: Int, in text: String, paragraphRanges: [NSRange]) -> Int? {
        guard let (segmentIndex, segment) = segmentContaining(index, in: paragraphRanges) else { return nil }
        let segmentEnd = segment.location + segment.length
        if index < segmentEnd, let segmentText = substring(of: text, range: segment) {
            let relative = max(0, index - segment.location)
            if let relativeNext = TextTokenizer.findIndex(ofNext: .sentence, startingAt: relative, in: segmentText) {
                let candidate = segment.location + relativeNext
                if candidate < segmentEnd {
                    return candidate
                }
            }
        }
        // The sentence containing `index` is the last one in its segment; move to the next segment's first sentence.
        let nextIndex = segmentIndex + 1
        guard nextIndex < paragraphRanges.count else { return nil }
        return firstSentenceStart(in: paragraphRanges[nextIndex], text: text)
    }

    /// Returns the start index of the first sentence within `segment`.
    private static func firstSentenceStart(in segment: NSRange, text: String) -> Int? {
        return sentenceSegment(startingAt: segment.location, in: text, paragraphRanges: [segment])?.location ?? segment.location
    }

    /// Returns the start index of the sentence immediately before `index`, bounded to paragraph segments. Looks within
    /// the segment containing `index`; if `index` is at that segment's first sentence, returns the last sentence start
    /// of the previous segment. Returns nil when there is no earlier sentence within `paragraphRanges`.
    static func previousSentenceStart(before index: Int, in text: String, paragraphRanges: [NSRange]) -> Int? {
        guard let (segmentIndex, segment) = segmentContaining(index, in: paragraphRanges) else { return nil }
        if index > segment.location, let segmentText = substring(of: text, range: segment) {
            let relative = index - segment.location
            if let relativeStart = TextTokenizer.findIndex(ofPreviousWhole: .sentence, beforeIndex: relative, in: segmentText) {
                return segment.location + relativeStart
            }
        }
        guard segmentIndex > 0 else { return nil }
        return lastSentenceStart(in: paragraphRanges[segmentIndex - 1], text: text)
    }

    /// Returns the start index of the last sentence within the last paragraph segment. Returns nil when there are no segments.
    static func lastSentenceStart(in text: String, paragraphRanges: [NSRange]) -> Int? {
        guard let last = paragraphRanges.last else { return nil }
        return lastSentenceStart(in: last, text: text)
    }

    private static func lastSentenceStart(in segment: NSRange, text: String) -> Int? {
        guard let segmentText = substring(of: text, range: segment) else { return nil }
        if let relativeStart = TextTokenizer.findIndex(ofPreviousWhole: .sentence, beforeIndex: segmentText.count, in: segmentText) {
            return segment.location + relativeStart
        }
        return segment.location
    }

    /// Returns the segment (and its index) that contains `index`, or the closest segment at or before it.
    private static func segmentContaining(_ index: Int, in paragraphRanges: [NSRange]) -> (index: Int, range: NSRange)? {
        var best: (Int, NSRange)?
        for (offset, range) in paragraphRanges.enumerated() {
            if index >= range.location, index < range.location + range.length {
                return (offset, range)
            }
            if range.location <= index {
                best = (offset, range)
            }
        }
        if let best { return best }
        return paragraphRanges.first.map { (0, $0) }
    }

    private static func substring(of text: String, range: NSRange) -> String? {
        guard range.location >= 0, range.length >= 0, range.location + range.length <= text.count else { return nil }
        let start = text.index(text.startIndex, offsetBy: range.location)
        let end = text.index(start, offsetBy: range.length)
        return String(text[start..<end])
    }
}
