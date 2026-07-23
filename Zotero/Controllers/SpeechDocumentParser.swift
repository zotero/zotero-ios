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
/// flagged `excluded` (page numbers, running headers/footers, …) are dropped. In-text citations (bracket/parenthesis
/// groups that are mostly reference links, and superscript reference markers) are stripped from the readable text so
/// they aren't read aloud. Each readable block is split by the page
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
        /// Bounding rects (PDF coordinate space) of the paragraph on its page. Metadata only; not used for highlighting.
        let rects: [CGRect]
        /// Per-character glyph rect (PDF coordinate space) aligned 1:1 with `text`, decoded from the structured document
        /// text's `textMap` geometry. `nil` for whitespace and any character without geometry. Used to highlight a
        /// character range without re-matching against the render layer.
        let charRects: [CGRect?]
    }

    /// Page-local unit handed to voice processors and the segment-query helpers. `pageOffset` is the character offset of
    /// the segment within its page's readable text, so page-text offsets and per-segment offsets are interchangeable.
    struct Segment {
        let text: String
        let pageOffset: Int
        /// Per-character glyph rect (PDF coordinate space) aligned 1:1 with `text`; see `Paragraph.charRects`.
        let charRects: [CGRect?]

        init(text: String, pageOffset: Int, charRects: [CGRect?] = []) {
            self.text = text
            self.pageOffset = pageOffset
            self.charRects = charRects
        }
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
    /// A bracket/parenthesis group is elided when at least this fraction of its inner non-whitespace characters is
    /// covered by reference links (matches the desktop reader's `LINK_GROUP_COVERAGE_THRESHOLD`).
    private static let linkGroupCoverageThreshold = 0.25

    /// A leaf text run with the metadata read-aloud needs: the page it renders on, whether it links to a reference
    /// (`refs`), whether it is superscript (`style.sup`), and its per-character glyph rects. `hasRefs`/`sup` drive
    /// in-text citation elision; `charRects` (aligned 1:1 with `text`) drives highlighting.
    private struct Run {
        let text: String
        let page: Int
        let hasRefs: Bool
        let sup: Bool
        let charRects: [CGRect?]
    }

    /// A half-open character range `[start, end)` within a segment's text.
    private struct TextRange {
        let start: Int
        var end: Int
    }

    /// A visible-text run's position within a segment's concatenated text, carrying the citation metadata used to decide
    /// whether the run (or a bracket group containing it) should be elided.
    private struct RunMapping {
        let absStart: Int
        let absEnd: Int
        let hasRefs: Bool
        let sup: Bool
    }

    /// One decoded glyph from a run's `textMap`: its rect (PDF coordinate space) and the page it renders on.
    private struct RunDatum {
        let rect: CGRect
        let pageIndex: Int
    }

    /// A single character's extent along the run's text axis (x for horizontal runs, y for vertical).
    private struct CharPosition {
        let start: Double
        let end: Double
    }

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
            var runs: [Run] = []
            collectRuns(in: block, fallbackPage: fallbackPage, into: &runs)
            appendSegments(from: runs, block: block, into: &paragraphs, pageLengths: &pageLengths)
        }

        return ParsedDocument(paragraphs: paragraphs, language: language)
    }

    /// Recursively gathers the leaf text runs of a block, assigning each run the page it is rendered on. Pure-spacing
    /// runs (and any run without its own `textMap`) inherit the page of the surrounding content.
    private static func collectRuns(in node: [String: Any], fallbackPage: Int, into runs: inout [Run]) {
        if let text = node["text"] as? String {
            guard !text.isEmpty else { return }
            let page = textMapPage(of: node) ?? runs.last?.page ?? fallbackPage
            let hasRefs = (node["refs"] as? [Any])?.isEmpty == false
            let sup = (node["style"] as? [String: Any])?["sup"] as? Bool == true
            runs.append(Run(text: text, page: page, hasRefs: hasRefs, sup: sup, charRects: charRects(of: node, page: page)))
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
        from runs: [Run],
        block: [String: Any],
        into paragraphs: inout [Paragraph],
        pageLengths: inout [Int: Int]
    ) {
        var currentPage: Int?
        var pageRuns: [Run] = []

        for run in runs {
            if let currentPage, currentPage != run.page {
                flush(page: currentPage, runs: pageRuns)
                pageRuns = []
            }
            currentPage = run.page
            pageRuns.append(run)
        }
        if let currentPage {
            flush(page: currentPage, runs: pageRuns)
        }

        func flush(page: Int, runs: [Run]) {
            let fallbackRect = boundingRect(of: rects(of: block, page: page))
            let stripped = strippingCitations(from: runs, fallbackRect: fallbackRect)

            // Trim leading/trailing whitespace off both text and rects together so they stay aligned.
            guard let first = stripped.characters.firstIndex(where: { !$0.isWhitespace }),
                  let last = stripped.characters.lastIndex(where: { !$0.isWhitespace }) else { return }
            let text = String(stripped.characters[first...last])
            let charRects = Array(stripped.charRects[first...last])

            let existingLength = pageLengths[page] ?? 0
            let offset = existingLength == 0 ? 0 : existingLength + segmentSeparator.count
            pageLengths[page] = offset + text.count
            paragraphs.append(Paragraph(text: text, page: page, pageOffset: offset, rects: rects(of: block, page: page), charRects: charRects))
        }
    }

    /// Concatenates a page's runs into its readable text (and the per-character rects aligned to it) with in-text
    /// citations removed. Skipped are bracket/parenthesis groups that are mostly reference links (e.g. "text [2]",
    /// "text (Smith, 2026)") and superscript reference markers (e.g. the "2" in "text²"). Mirrors the desktop reader's
    /// `getElidedRanges`. Runs still contribute their text and character positions, but only runs with visible text act
    /// as reference-coverage mappings — matching the desktop, where whitespace-only nodes anchor nothing. Runs whose
    /// `textMap` carried no geometry fall back to the block's bounding rect for their visible characters.
    private static func strippingCitations(from runs: [Run], fallbackRect: CGRect?) -> (characters: [Character], charRects: [CGRect?]) {
        var characters: [Character] = []
        var charRects: [CGRect?] = []
        var mappings: [RunMapping] = []
        for run in runs {
            let runCharacters = Array(run.text)
            let absStart = characters.count
            characters.append(contentsOf: runCharacters)
            if run.charRects.contains(where: { $0 != nil }) {
                charRects.append(contentsOf: run.charRects)
            } else if let fallbackRect {
                charRects.append(contentsOf: runCharacters.map { isSDTWhitespace($0) ? nil : fallbackRect })
            } else {
                charRects.append(contentsOf: run.charRects)
            }
            if runCharacters.contains(where: { !$0.isWhitespace }) {
                mappings.append(RunMapping(absStart: absStart, absEnd: characters.count, hasRefs: run.hasRefs, sup: run.sup))
            }
        }

        let elided = elidedRanges(in: characters, mappings: mappings)
        guard !elided.isEmpty else { return (characters, charRects) }

        // Keep every character (and its rect) not covered by an elided range (ranges are sorted, merged, non-overlapping).
        var keptCharacters: [Character] = []
        var keptRects: [CGRect?] = []
        var cursor = 0
        for range in elided {
            if range.start > cursor {
                keptCharacters.append(contentsOf: characters[cursor..<range.start])
                keptRects.append(contentsOf: charRects[cursor..<range.start])
            }
            cursor = max(cursor, range.end)
        }
        if cursor < characters.count {
            keptCharacters.append(contentsOf: characters[cursor..<characters.count])
            keptRects.append(contentsOf: charRects[cursor..<characters.count])
        }
        return (keptCharacters, keptRects)
    }

    /// Ranges of `text` that read-aloud skips: bracket/parenthesis groups that are mostly linked (citation) text, plus
    /// superscript reference markers. Returns merged, ascending, non-overlapping ranges.
    private static func elidedRanges(in text: [Character], mappings: [RunMapping]) -> [TextRange] {
        var ranges: [TextRange] = []
        for (open, close) in [(Character("["), Character("]")), (Character("("), Character(")"))] {
            var stack: [Int] = []
            for index in text.indices {
                if text[index] == open {
                    stack.append(index)
                } else if text[index] == close, let start = stack.popLast(), isLinkGroup(text: text, mappings: mappings, start: start, end: index + 1) {
                    ranges.append(TextRange(start: start, end: index + 1))
                }
            }
        }
        for mapping in mappings where mapping.hasRefs && mapping.sup {
            ranges.append(TextRange(start: mapping.absStart, end: mapping.absEnd))
        }
        return mergeRanges(ranges)
    }

    /// Whether the group `[start, end)` (brackets included) is a citation: it must contain some reference-linked,
    /// non-whitespace text, and linked characters must make up at least `linkGroupCoverageThreshold` of its inner
    /// (bracket-excluded) non-whitespace content. This keeps plain asides like "(see above)" while dropping "[2]".
    private static func isLinkGroup(text: [Character], mappings: [RunMapping], start: Int, end: Int) -> Bool {
        var linkedCharacters = 0
        for mapping in mappings where mapping.hasRefs {
            let from = max(start, mapping.absStart)
            let to = min(end, mapping.absEnd)
            for index in from..<max(from, to) where !text[index].isWhitespace {
                linkedCharacters += 1
            }
        }
        guard linkedCharacters > 0 else { return false }

        var contentCharacters = 0
        for index in (start + 1)..<max(start + 1, end - 1) where !text[index].isWhitespace {
            contentCharacters += 1
        }
        return contentCharacters > 0 && Double(linkedCharacters) / Double(contentCharacters) >= linkGroupCoverageThreshold
    }

    /// Sorts ranges and coalesces touching or overlapping ones into a minimal ascending set.
    private static func mergeRanges(_ ranges: [TextRange]) -> [TextRange] {
        let sorted = ranges
            .filter { $0.end > $0.start }
            .sorted { $0.start != $1.start ? $0.start < $1.start : $0.end < $1.end }
        var merged: [TextRange] = []
        for range in sorted {
            if var last = merged.last, range.start <= last.end {
                last.end = max(last.end, range.end)
                merged[merged.count - 1] = last
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    // MARK: - Geometry (textMap → per-character rects)

    /// Decodes a leaf run node's `textMap` into a per-character rect array aligned 1:1 with the node's `text`.
    /// The `textMap` run data carries one entry per non-whitespace character (see `buildRunData`); whitespace
    /// characters, characters past the available run data, and characters that render on a different page than the
    /// run's assigned `page` get `nil`. Mirrors the desktop `PDFPositionMapper` span-to-rect alignment.
    private static func charRects(of node: [String: Any], page: Int) -> [CGRect?] {
        let characters = Array((node["text"] as? String) ?? "")
        guard let anchor = node["anchor"] as? [String: Any], let textMap = anchor["textMap"] as? String else {
            return Array(repeating: nil, count: characters.count)
        }
        let runData = buildRunData(parseTextMap(textMap))
        guard !runData.isEmpty else { return Array(repeating: nil, count: characters.count) }

        var result: [CGRect?] = []
        result.reserveCapacity(characters.count)
        var runIndex = 0
        for character in characters {
            if isSDTWhitespace(character) {
                result.append(nil)
            } else if runIndex < runData.count {
                let datum = runData[runIndex]
                runIndex += 1
                result.append(datum.pageIndex == page ? datum.rect : nil)
            } else {
                result.append(nil)
            }
        }
        return result
    }

    /// Parses a `textMap` JSON string into its array of runs (`[[header, pageIndex, minX, minY, maxX, maxY, ...widths]]`).
    private static func parseTextMap(_ textMap: String) -> [[Any]] {
        guard let data = textMap.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [[Any]] else { return [] }
        return parsed
    }

    /// Reconstructs one rect (PDF coordinate space) per non-whitespace character from parsed `textMap` runs.
    /// Each run is `[header, pageIndex, minX, minY, maxX, maxY, ...widths]`: header bit 0 marks a trailing soft hyphen
    /// (its position is dropped), header bits 1-2 encode the axis direction (1 or 3 = vertical). Widths are either a
    /// numeric advance or a `[delta, width]` pair. Ports the reader's `buildRunData`/`reconstructCharPositions`.
    private static func buildRunData(_ runs: [[Any]]) -> [RunDatum] {
        var data: [RunDatum] = []
        for run in runs {
            guard run.count >= 6,
                  let header = intValue(run[0]),
                  let pageIndex = intValue(run[1]),
                  let minX = doubleValue(run[2]),
                  let minY = doubleValue(run[3]),
                  let maxX = doubleValue(run[4]),
                  let maxY = doubleValue(run[5]) else { continue }
            let axisDirection = (header >> 1) & 0b11
            let vertical = axisDirection == 1 || axisDirection == 3
            var positions = reconstructCharPositions(run: run, vertical: vertical, minX: minX, minY: minY, maxX: maxX, maxY: maxY)
            // Drop the trailing soft-hyphen position (header bit 0): it is not read and has no character.
            if (header & 1) != 0, !positions.isEmpty {
                positions.removeLast()
            }
            for position in positions where position.start.isFinite && position.end.isFinite {
                let rect = vertical
                    ? CGRect(x: minX, y: position.start, width: maxX - minX, height: position.end - position.start)
                    : CGRect(x: position.start, y: minY, width: position.end - position.start, height: maxY - minY)
                data.append(RunDatum(rect: rect, pageIndex: pageIndex))
            }
        }
        return data
    }

    /// Reconstructs the per-character extents along a run's text axis from its width entries (see `buildRunData`).
    private static func reconstructCharPositions(run: [Any], vertical: Bool, minX: Double, minY: Double, maxX: Double, maxY: Double) -> [CharPosition] {
        let start = vertical ? minY : minX
        let end = vertical ? maxY : maxX
        let widths = run.count > 6 ? Array(run[6...]) : []
        // Single-character run: no widths, the whole bbox is the character.
        guard !widths.isEmpty else { return [CharPosition(start: start, end: end)] }

        var positions: [CharPosition] = []
        var cursor = start
        for width in widths {
            if let pair = width as? [Any], pair.count >= 2, let delta = doubleValue(pair[0]), let advance = doubleValue(pair[1]) {
                cursor += delta
                positions.append(CharPosition(start: cursor, end: cursor + advance))
                cursor += advance
            } else if let advance = doubleValue(width) {
                positions.append(CharPosition(start: cursor, end: cursor + advance))
                cursor += advance
            }
        }
        return positions
    }

    /// Whitespace as the structured document text's PDF layout defines it (space, newline, tab) — the exact set used
    /// when the `textMap` was built, so per-character rect alignment stays in sync. Broader than this would misalign.
    private static func isSDTWhitespace(_ character: Character) -> Bool {
        return character == " " || character == "\n" || character == "\t"
    }

    // MARK: - Highlight rects

    /// Merged per-line rects (PDF coordinate space) covering `range` (page-text character offsets) across `segments`.
    /// Reads the precomputed per-character rects rather than re-matching text against the render layer, so highlighting
    /// stays correct even where the readable text differs from the rendered glyphs (e.g. elided citations).
    static func pdfLineRects(forRange range: NSRange, in segments: [Segment]) -> [CGRect] {
        guard range.length > 0 else { return [] }
        let rangeStart = range.location
        let rangeEnd = range.location + range.length
        var rects: [CGRect] = []
        for segment in segments {
            let segmentStart = segment.pageOffset
            let segmentEnd = segment.pageOffset + segment.text.count
            let from = max(rangeStart, segmentStart)
            let to = min(rangeEnd, segmentEnd)
            guard from < to else { continue }
            for index in (from - segmentStart)..<(to - segmentStart) where index < segment.charRects.count {
                if let rect = segment.charRects[index] {
                    rects.append(rect)
                }
            }
        }
        return mergeLineRects(rects)
    }

    /// Merges consecutive same-line rects into one rect per visual line (rects arrive in reading order). Port of the
    /// desktop `mergeLineRects`.
    private static func mergeLineRects(_ rects: [CGRect]) -> [CGRect] {
        var merged: [CGRect] = []
        for rect in rects {
            if let last = merged.last, sameLine(last, rect) {
                merged[merged.count - 1] = last.union(rect)
            } else {
                merged.append(rect)
            }
        }
        return merged
    }

    /// Whether two rects sit on the same visual line: their vertical overlap is at least 60% of the shorter one's height.
    private static func sameLine(_ a: CGRect, _ b: CGRect) -> Bool {
        let overlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        let minHeight = max(0.001, min(a.height, b.height))
        return overlap / minHeight >= 0.6
    }

    /// Bounding box of `rects`, or nil when there are none. Used as the coarse fallback rect for runs lacking geometry.
    private static func boundingRect(of rects: [CGRect]) -> CGRect? {
        guard var union = rects.first else { return nil }
        for rect in rects.dropFirst() {
            union = union.union(rect)
        }
        return union
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
