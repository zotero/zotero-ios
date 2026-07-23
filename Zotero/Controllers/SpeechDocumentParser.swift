//
//  SpeechDocumentParser.swift
//  Zotero
//
//  Created by Michal Rentka on 2025.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import CoreGraphics
import Foundation
import NaturalLanguage

/// Turns a materialized `SDTPack` document into the read-aloud paragraph model.
///
/// Only readable blocks (`paragraph` and `list`) are kept; headings, images, math, preformatted blocks and anything
/// flagged `excluded` (page numbers, running headers/footers, …) are dropped. Each readable block is split by the page
/// its runs belong to (a paragraph can span a page boundary), so every resulting `Paragraph` lives on exactly one page
/// and its text matches what PSPDFKit renders there. `pageOffset` is the paragraph's character offset within its page's
/// readable text (paragraphs on a page are joined by a blank line), which lets callers translate between a paragraph
/// position and an in-page position without materializing the page text.
enum SpeechDocumentParser {
    /// A single readable paragraph (or the per-page slice of a paragraph that spans pages).
    struct Paragraph {
        let text: String
        /// 0-based structured-document-text page index the paragraph renders on.
        let page: Int
        /// Character offset of this paragraph within its page's readable text.
        let pageOffset: Int
        /// Bounding rects (PDF coordinate space) of the paragraph on its page. Metadata only; not used for highlighting yet.
        let rects: [CGRect]
    }

    /// Page-local unit handed to voice processors and the segment-query helpers. `pageOffset` is the character offset of
    /// the segment within its page's readable text, so page-text offsets and per-segment offsets are interchangeable.
    struct Segment {
        let text: String
        let pageOffset: Int
    }

    struct ParsedDocument {
        /// Readable paragraphs in document reading order.
        let paragraphs: [Paragraph]
        /// Document language (BCP-47) from metadata, if present.
        let language: String?
    }

    private static let classesTypesToIgnore: Set<String> = ["excluded", "auxiliary"]
    /// Characters separating two paragraphs within a page's readable text.
    static let segmentSeparator = "\n\n"

    /// Parses the `materialize()` output of an `SDTPack` into the read-aloud paragraph model.
    static func parse(materialized: [String: Any]) -> ParsedDocument {
        let language = language(from: materialized)
        guard let content = materialized["content"] as? [[String: Any]] else {
            return ParsedDocument(paragraphs: [], language: language)
        }

        var paragraphs: [Paragraph] = []
        var pageLengths: [Int: Int] = [:]

        for block in content {
            if let flowClass = block["flowClass"] as? String, classesTypesToIgnore.contains(flowClass) { continue }
            let fallbackPage = startPage(of: block) ?? pageLengths.keys.max() ?? 0
            var runs: [(text: String, page: Int)] = []
            collectRuns(in: block, fallbackPage: fallbackPage, into: &runs)
            appendSegments(from: runs, block: block, into: &paragraphs, pageLengths: &pageLengths)
        }

        return ParsedDocument(paragraphs: paragraphs, language: language)
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

    /// Groups consecutive runs by page into segments and appends each as a `Paragraph`, tracking per-page text length so
    /// `pageOffset` matches the position the segment would have in the page's joined readable text.
    private static func appendSegments(
        from runs: [(text: String, page: Int)],
        block: [String: Any],
        into paragraphs: inout [Paragraph],
        pageLengths: inout [Int: Int]
    ) {
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
            let existingLength = pageLengths[page] ?? 0
            let offset = existingLength == 0 ? 0 : existingLength + segmentSeparator.count
            pageLengths[page] = offset + trimmed.count
            paragraphs.append(Paragraph(text: trimmed, page: page, pageOffset: offset, rects: rects(of: block, page: page)))
        }
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

    /// Builds the paragraph's bounding rects for `page` from `anchor.pageRects` (entries are `[page, x0, y0, x1, y1]`, PDF space).
    private static func rects(of block: [String: Any], page: Int) -> [CGRect] {
        guard let anchor = block["anchor"] as? [String: Any],
              let pageRects = anchor["pageRects"] as? [[Any]] else { return [] }
        return pageRects.compactMap { rect in
            guard rect.count >= 5, intValue(rect[0]) == page,
                  let x0 = doubleValue(rect[1]), let y0 = doubleValue(rect[2]),
                  let x1 = doubleValue(rect[3]), let y1 = doubleValue(rect[4]) else { return nil }
            return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        }
    }

    private static func intValue(_ value: Any) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private static func doubleValue(_ value: Any) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }
}

// MARK: - Segment queries

/// Navigation over a page's paragraph `Segment`s. Sentences are detected with `TextTokenizer` on an individual segment's
/// text, so a sentence can never span a paragraph boundary (each segment is its own string). All indices are page-text
/// character offsets (a segment's own text starts at its `pageOffset`). Shared by `SpeechManager` (forward/backward
/// navigation) and `RemoteVoiceProcessor` (playback segmentation) so both segment identically.
extension SpeechDocumentParser {
    /// Returns the range from `index` to the end of the segment that covers it (or the whole next segment when `index`
    /// falls in the gap between segments). Returns nil when `index` is past the last segment.
    static func paragraphRange(startingAt index: Int, in segments: [Segment]) -> NSRange? {
        guard let (_, segment) = segmentContaining(index, in: segments) else { return nil }
        let end = segment.pageOffset + segment.text.count
        let start = max(index, segment.pageOffset)
        return NSRange(location: start, length: end - start)
    }

    /// Returns the next sentence range starting at `index`, bounded to the segment that contains it. Returns nil when
    /// `index` is past the last segment.
    static func sentenceRange(startingAt index: Int, in segments: [Segment]) -> NSRange? {
        guard let (_, segment) = segmentContaining(index, in: segments) else { return nil }
        let intra = max(0, index - segment.pageOffset)
        guard let sentence = TextTokenizer.findSentence(startingAt: intra, in: segment.text) else { return nil }
        return NSRange(location: segment.pageOffset + sentence.range.location, length: sentence.range.length)
    }

    /// Returns the start index of the sentence following the one containing `index`, rolling into the next segment when
    /// `index` is in the last sentence of its segment. Returns nil past the last sentence. Advances past the containing
    /// sentence (used for forward navigation, where `index` may be mid-sentence).
    static func nextSentenceStart(after index: Int, in segments: [Segment]) -> Int? {
        guard let (segmentIndex, segment) = segmentContaining(index, in: segments) else { return nil }
        let segmentEnd = segment.pageOffset + segment.text.count
        if index < segmentEnd {
            let intra = max(0, index - segment.pageOffset)
            if let relativeNext = TextTokenizer.nextSentenceStart(after: intra, in: segment.text) {
                let candidate = segment.pageOffset + relativeNext
                if candidate < segmentEnd {
                    return candidate
                }
            }
        }
        let nextIndex = segmentIndex + 1
        guard nextIndex < segments.count else { return nil }
        return firstSentenceStart(in: segments[nextIndex])
    }

    /// Returns the start index of the sentence immediately before `index`, rolling back into the previous segment's last
    /// sentence when `index` is at its segment's first sentence. Returns nil when there is no earlier sentence.
    static func previousSentenceStart(before index: Int, in segments: [Segment]) -> Int? {
        guard let (segmentIndex, segment) = segmentContaining(index, in: segments) else { return nil }
        if index > segment.pageOffset {
            let intra = index - segment.pageOffset
            if let relativeStart = TextTokenizer.previousSentenceStart(before: intra, in: segment.text) {
                return segment.pageOffset + relativeStart
            }
        }
        guard segmentIndex > 0 else { return nil }
        return lastSentenceStart(in: segments[segmentIndex - 1])
    }

    /// Returns the start index of the last sentence in the last segment. Returns nil when there are no segments.
    static func lastSentenceStart(in segments: [Segment]) -> Int? {
        guard let last = segments.last else { return nil }
        return lastSentenceStart(in: last)
    }

    private static func firstSentenceStart(in segment: Segment) -> Int {
        return segment.pageOffset + (TextTokenizer.findSentence(startingAt: 0, in: segment.text)?.range.location ?? 0)
    }

    private static func lastSentenceStart(in segment: Segment) -> Int {
        return segment.pageOffset + (TextTokenizer.previousSentenceStart(before: segment.text.count, in: segment.text) ?? 0)
    }

    /// Returns the segment (and its index) whose text ends after `index` — i.e. the segment containing `index`, or the
    /// next one when `index` is in the gap between segments. Segments are ordered by `pageOffset`.
    private static func segmentContaining(_ index: Int, in segments: [Segment]) -> (index: Int, segment: Segment)? {
        for (offset, segment) in segments.enumerated() where index < segment.pageOffset + segment.text.count {
            return (offset, segment)
        }
        return nil
    }
}

// MARK: - Highlight units

/// Highlight units over a page's segments, parameterized by granularity. A `.paragraph` unit is a whole segment; a
/// `.sentence` unit is a sentence within a segment. All ranges are page-text character offsets. Used by
/// `SpeechHighlightSessionManager` so its unit detection comes straight from the structured document text.
extension SpeechDocumentParser {
    /// The full unit (whole segment for `.paragraph`, containing sentence for `.sentence`) covering `index`.
    static func unitRange(containing index: Int, granularity: NLTokenUnit, in segments: [Segment]) -> NSRange? {
        guard let (_, segment) = segmentContaining(index, in: segments) else { return nil }
        if granularity == .paragraph {
            return NSRange(location: segment.pageOffset, length: segment.text.count)
        }
        let intra = max(0, index - segment.pageOffset)
        guard let sentence = TextTokenizer.findSentenceContaining(index: intra, in: segment.text) else { return nil }
        return NSRange(location: segment.pageOffset + sentence.range.location, length: sentence.range.length)
    }

    /// The first unit on the page.
    static func firstUnitRange(granularity: NLTokenUnit, in segments: [Segment]) -> NSRange? {
        guard let first = segments.first else { return nil }
        if granularity == .paragraph {
            return NSRange(location: first.pageOffset, length: first.text.count)
        }
        return sentenceRange(startingAt: first.pageOffset, in: segments)
    }

    /// The last unit on the page.
    static func lastUnitRange(granularity: NLTokenUnit, in segments: [Segment]) -> NSRange? {
        guard let last = segments.last else { return nil }
        if granularity == .paragraph {
            return NSRange(location: last.pageOffset, length: last.text.count)
        }
        guard let start = lastSentenceStart(in: segments) else { return nil }
        return sentenceRange(startingAt: start, in: segments)
    }

    /// The unit following the one that ends at `range`'s end, on the same page. nil past the last unit.
    static func nextUnitRange(afterEndOf range: NSRange, granularity: NLTokenUnit, in segments: [Segment]) -> NSRange? {
        let end = range.location + range.length
        if granularity == .paragraph {
            guard let next = segments.first(where: { $0.pageOffset >= end }) else { return nil }
            return NSRange(location: next.pageOffset, length: next.text.count)
        }
        guard let start = nextSentenceStart(after: end, in: segments) else { return nil }
        return sentenceRange(startingAt: start, in: segments)
    }

    /// The unit immediately before the one starting at `location`, on the same page. nil at the first unit.
    static func previousUnitRange(before location: Int, granularity: NLTokenUnit, in segments: [Segment]) -> NSRange? {
        if granularity == .paragraph {
            guard let previous = segments.last(where: { $0.pageOffset < location }) else { return nil }
            return NSRange(location: previous.pageOffset, length: previous.text.count)
        }
        guard let start = previousSentenceStart(before: location, in: segments) else { return nil }
        return sentenceRange(startingAt: start, in: segments)
    }
}
