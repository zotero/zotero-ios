//
//  SDTReadAloudSegments.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 21.10.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import NaturalLanguage

/// Builds read aloud segments for HTML/EPUB from structured document text, without the reader. Native port of
/// `buildSDTReadAloudSegments` from the reader (`src/common/read-aloud/sdt-segments.ts`): every logical paragraph (a part
/// chain) becomes the concatenated text of its text nodes, with linked citation groups and superscript reference markers
/// left out of the spoken text, and each segment carries the SDT position it was read from.
///
/// Unlike the reader, which splits paragraphs with `sentencex`, sentences are split by `TextTokenizer` (in one pass per
/// paragraph), the same splitting playback uses.
enum SDTReadAloudSegments {
    /// A text node's contribution to a chain's text: `[absStart, absEnd)` in the chain text corresponds to `[start, end)` in
    /// the node text.
    private struct Mapping {
        let ref: SDTContent.Ref
        var start: Int
        var end: Int
        var absStart: Int
        var absEnd: Int
        let hasRefs: Bool
        let isSuperscript: Bool
    }

    /// The text of one logical paragraph, in UTF-16 code units, with mappings from offsets back to text nodes.
    private struct ChainText {
        let text: [UInt16]
        let mappings: [Mapping]
    }

    private struct TextRange {
        var start: Int
        var end: Int
    }

    /// Drop a bracket/parenthesis group when at least this fraction of its non-whitespace content is linked text, so citation
    /// and note marker groups drop, while prose asides that merely contain a link survive.
    private static let linkGroupCoverageThreshold = 0.25

    static func segments(from structure: SDTContent.Node) -> [SpeechReaderSegment] {
        var segments: [SpeechReaderSegment] = []
        // One tokenizer for the whole document, set up once and reused for every paragraph.
        let tokenizer = NLTokenizer(unit: .sentence)
        for chain in chainTexts(in: structure) {
            appendSegments(of: chain, tokenizer: tokenizer, to: &segments)
        }
        return segments
    }

    // MARK: - Chains

    /// Walks the leaf blocks, joins part chains (paragraphs split across pages/columns) and builds the text of each.
    private static func chainTexts(in structure: SDTContent.Node) -> [ChainText] {
        let content = (structure["content"] as? [Any]) ?? []
        var chains: [ChainText] = []
        var emitted: Set<String> = []
        let include: (SDTContent.Ref) -> Bool = { ref in
            guard let index = ref.first, index < content.count else { return true }
            return ((content[index] as? SDTContent.Node)?["flowClass"] as? String) != "excluded"
        }

        SDTContent.walkContentRangeLeafBlocks(content: content, range: ([0], [content.count])) { leaf in
            guard include(leaf.ref), !emitted.contains(SDTContent.refKey(leaf.ref)) else { return }
            let chain = SDTContent.partChain(in: structure, ref: leaf.ref, include: { ref, _ in include(ref) })
            guard !chain.contains(where: { emitted.contains(SDTContent.refKey($0.ref)) }) else { return }
            for part in chain {
                emitted.insert(SDTContent.refKey(part.ref))
            }
            let text = chainText(of: chain)
            if SDTContent.containsNonWhitespace(text.text) {
                chains.append(text)
            }
        }
        return chains
    }

    private static func chainText(of chain: [SDTContent.Part]) -> ChainText {
        var text: [UInt16] = []
        var mappings: [Mapping] = []

        for (index, part) in chain.enumerated() {
            if index > 0 {
                let previousBlock = chain[index - 1].block
                if SDTContent.shouldDropHardHyphenAtPartBoundary(previousBlock: previousBlock, nextBlock: part.block) && text.last == 0x2D {
                    text.removeLast()
                    if var last = mappings.popLast() {
                        last.absEnd -= 1
                        last.end -= 1
                        if last.absEnd > last.absStart {
                            mappings.append(last)
                        }
                    }
                }
                text += SDTContent.partBoundarySeparator(previousBlock: previousBlock, nextBlock: part.block)
            }

            guard let nodes = part.block["content"] as? [Any] else { continue }
            for (nodeIndex, node) in nodes.enumerated() {
                guard let node = node as? SDTContent.Node, let nodeText = SDTContent.text(of: node), !nodeText.isEmpty else { continue }
                // Whitespace-only nodes keep their text (word separation) but get no mapping, so positions snap inward to
                // nodes with visible text.
                if SDTContent.containsNonWhitespace(nodeText) {
                    mappings.append(
                        Mapping(
                            ref: part.ref + [nodeIndex],
                            start: 0,
                            end: nodeText.count,
                            absStart: text.count,
                            absEnd: text.count + nodeText.count,
                            hasRefs: (node["refs"] as? [Any])?.isEmpty == false,
                            isSuperscript: SDTContent.isTruthy((node["style"] as? SDTContent.Node)?["sup"])
                        )
                    )
                }
                text += nodeText
            }
        }

        return compact(text: text, mappings: mappings, removing: elidedRanges(in: text, mappings: mappings))
    }

    // MARK: - Elision

    /// Ranges read aloud skips: bracket/parenthesis groups that are mostly linked text, and superscript link markers.
    private static func elidedRanges(in text: [UInt16], mappings: [Mapping]) -> [TextRange] {
        var ranges: [TextRange] = []
        for (open, close) in [(UInt16(0x5B), UInt16(0x5D)), (UInt16(0x28), UInt16(0x29))] {
            var stack: [Int] = []
            for index in 0..<text.count {
                if text[index] == open {
                    stack.append(index)
                } else if text[index] == close, let start = stack.popLast(), isLinkGroup(text: text, mappings: mappings, start: start, end: index + 1) {
                    ranges.append(TextRange(start: start, end: index + 1))
                }
            }
        }
        for mapping in mappings where mapping.hasRefs && mapping.isSuperscript {
            ranges.append(TextRange(start: mapping.absStart, end: mapping.absEnd))
        }
        return merged(ranges)
    }

    private static func isLinkGroup(text: [UInt16], mappings: [Mapping], start: Int, end: Int) -> Bool {
        var linkedChars = 0
        for mapping in mappings where mapping.hasRefs {
            let from = max(start, mapping.absStart)
            let to = min(end, mapping.absEnd)
            guard from < to else { continue }
            linkedChars += text[from..<to].filter({ !SDTContent.isWhitespace($0) }).count
        }
        guard linkedChars > 0, start + 1 < end - 1 else { return false }
        let contentChars = text[(start + 1)..<(end - 1)].filter({ !SDTContent.isWhitespace($0) }).count
        return contentChars > 0 && Double(linkedChars) / Double(contentChars) >= linkGroupCoverageThreshold
    }

    private static func merged(_ ranges: [TextRange]) -> [TextRange] {
        let sorted = ranges
            .filter({ $0.end > $0.start })
            .sorted(by: { $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start })
        var merged: [TextRange] = []
        for range in sorted {
            if let last = merged.last, range.start <= last.end {
                merged[merged.count - 1].end = max(last.end, range.end)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    /// Removes `ranges` from the text and re-splits the mappings around them.
    private static func compact(text: [UInt16], mappings: [Mapping], removing ranges: [TextRange]) -> ChainText {
        guard !ranges.isEmpty else { return ChainText(text: text, mappings: mappings) }

        // Complement of the elided ranges: each kept slice of the text, with where it lands in the compacted text.
        var kept: [(start: Int, end: Int, compactedStart: Int)] = []
        var cursor = 0
        var compactedLength = 0
        for range in ranges + [TextRange(start: text.count, end: text.count)] {
            if range.start > cursor {
                kept.append((cursor, range.start, compactedLength))
                compactedLength += range.start - cursor
            }
            cursor = max(cursor, range.end)
        }

        var compactedMappings: [Mapping] = []
        for mapping in mappings {
            for slice in kept {
                let start = max(mapping.absStart, slice.start)
                let end = min(mapping.absEnd, slice.end)
                guard end > start, SDTContent.containsNonWhitespace(text[start..<end]) else { continue }
                var compacted = mapping
                compacted.start = mapping.start + start - mapping.absStart
                compacted.end = mapping.start + end - mapping.absStart
                compacted.absStart = slice.compactedStart + start - slice.start
                compacted.absEnd = slice.compactedStart + end - slice.start
                compactedMappings.append(compacted)
            }
        }

        return ChainText(text: kept.flatMap({ text[$0.start..<$0.end] }), mappings: compactedMappings)
    }

    // MARK: - Segments

    /// Splits the chain into sentences and appends a segment for each, the first one starting the paragraph.
    private static func appendSegments(of chain: ChainText, tokenizer: NLTokenizer, to segments: inout [SpeechReaderSegment]) {
        let firstIndex = segments.count
        // Decoding keeps the UTF-16 length (an unpaired surrogate becomes a single replacement character), so the string's
        // UTF-16 offsets are the chain's.
        let string = String(decoding: chain.text, as: UTF16.self)
        // `TextTokenizer` works in `Character` offsets, the chain in UTF-16 offsets.
        var utf16Offsets: [Int] = [0]
        for character in string {
            utf16Offsets.append(utf16Offsets[utf16Offsets.count - 1] + character.utf16.count)
        }

        let sentenceRanges = TextTokenizer.sentenceRanges(in: string, tokenizer: tokenizer)
        for range in sentenceRanges {
            appendSegment(chain: chain, rawStart: utf16Offsets[range.location], rawEnd: utf16Offsets[NSMaxRange(range)])
        }
        if sentenceRanges.isEmpty {
            appendSegment(chain: chain, rawStart: 0, rawEnd: chain.text.count)
        }

        func appendSegment(chain: ChainText, rawStart: Int, rawEnd: Int) {
            let text = normalized(chain.text[rawStart..<rawEnd])
            guard !text.isEmpty, let sdtPosition = position(in: chain, rawStart: rawStart, rawEnd: rawEnd) else { return }
            segments.append(SpeechReaderSegment(text: text, start: sdtPosition.start, end: sdtPosition.end, isParagraphStart: segments.count == firstIndex))
        }
    }

    private static func position(in chain: ChainText, rawStart: Int, rawEnd: Int) -> SDTPosition? {
        guard let start = point(in: chain, offset: rawStart, isEnd: false), let end = point(in: chain, offset: rawEnd, isEnd: true) else { return nil }
        return SDTPosition(start: start, end: end)
    }

    /// Converts an offset in the chain text to an SDT content point. Offsets between mappings (part separators, skipped
    /// reference markers) snap inward.
    private static func point(in chain: ChainText, offset: Int, isEnd: Bool) -> [Int]? {
        let mappings = chain.mappings
        guard let first = mappings.first, let last = mappings.last else { return nil }
        if isEnd {
            // Last mapping that starts before the offset.
            if let mapping = mappings.last(where: { $0.absStart < offset }) {
                return mapping.ref + [min(offset, mapping.absEnd) - mapping.absStart]
            }
            return first.ref + [0]
        }
        // First mapping that ends past the offset.
        if let mapping = mappings.first(where: { $0.absEnd > offset }) {
            return mapping.ref + [max(offset, mapping.absStart) - mapping.absStart]
        }
        return last.ref + [last.absEnd - last.absStart]
    }

    /// Collapses whitespace runs to a single space and trims, as the text sent to the TTS server.
    private static func normalized(_ units: ArraySlice<UInt16>) -> String {
        var result: [UInt16] = []
        var pendingSpace = false
        for unit in units {
            if SDTContent.isWhitespace(unit) {
                pendingSpace = !result.isEmpty
                continue
            }
            if pendingSpace {
                result.append(SDTContent.space)
                pendingSpace = false
            }
            result.append(unit)
        }
        return String(decoding: result, as: UTF16.self)
    }
}
