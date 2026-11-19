//
//  SDTFulltext.swift
//  ZoteroTests
//
//  Created by Miltiadis Vasilakis on 21.10.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

@testable import Zotero

/// Test-only port of `getFulltextFromStructuredText` from `zotero/structured-document-text` (`src/fulltext.js`). It's built
/// on the same `SDTContent` primitives read aloud uses (leaf block walking, part chains, part boundary separators, hyphen
/// dropping), so that those can be checked against the expected full text fixtures of the submodule.
enum SDTFulltext {
    private struct Entry {
        var index: Int
        let ref: SDTContent.Ref
        let block: SDTContent.Node
        let text: [UInt16]
        let startPoint: SDTContent.Point
        let endPoint: SDTContent.Point
    }

    private enum PlainTextSegment {
        case text(ref: SDTContent.Ref, text: [UInt16])
        case separator([UInt16])

        var isText: Bool {
            switch self {
            case .text:
                return true

            case .separator:
                return false
            }
        }
    }

    static func fulltext(from structure: SDTContent.Node, pageIndexes: [Int]) -> [UInt16] {
        let content = (structure["content"] as? [Any]) ?? []
        let pages = ((structure["catalog"] as? SDTContent.Node)?["pages"] as? [Any]) ?? []
        var entries: [Entry] = []
        var entryIndexesByRef: [SDTContent.Ref: [Int]] = [:]
        var blockTexts: [[UInt16]] = []
        var previous: Entry?

        for pageIndex in pageIndexes {
            guard pageIndex >= 0, pageIndex < pages.count, let page = pages[pageIndex] as? SDTContent.Node else { continue }
            for var entry in rangeBlockTexts(content: content, rangeValue: page["contentRange"]) where !entry.text.isEmpty {
                entry.index = entries.count
                entries.append(entry)
                entryIndexesByRef[entry.ref, default: []].append(entry.index)
            }
        }

        var emittedIndexes: Set<Int> = []
        for entry in entries where !emittedIndexes.contains(entry.index) {
            let chain = selectedPartChain(from: entry, entries: entries, entryIndexesByRef: entryIndexesByRef, emittedIndexes: emittedIndexes)
            for (index, part) in chain.enumerated() {
                if index == 0 {
                    if let previous {
                        blockTexts.append(entrySeparator(previous: previous, current: part))
                    }
                } else if SDTContent.sameRef(chain[index - 1].ref, part.ref) {
                    blockTexts.append(entrySeparator(previous: chain[index - 1], current: part))
                } else {
                    if SDTContent.shouldDropHardHyphenAtPartBoundary(previousBlock: chain[index - 1].block, nextBlock: part.block), blockTexts.last?.last == SDTContent.hyphen {
                        blockTexts[blockTexts.count - 1].removeLast()
                    }
                    blockTexts.append(SDTContent.partBoundarySeparator(previousBlock: chain[index - 1].block, nextBlock: part.block))
                }
                blockTexts.append(part.text)
                emittedIndexes.insert(part.index)
                previous = part
            }
        }

        return trimmed(removingTrailingSpacesAndTabsOfLines(in: blockTexts.flatMap({ $0 })))
    }

    // MARK: - Chains

    private static func selectedPartChain(from entry: Entry, entries: [Entry], entryIndexesByRef: [SDTContent.Ref: [Int]], emittedIndexes: Set<Int>) -> [Entry] {
        var chain: [Entry] = []
        var seenRefs: Set<SDTContent.Ref> = []
        var current: Entry? = entry
        while let entry = current, !emittedIndexes.contains(entry.index) {
            guard seenRefs.insert(entry.ref).inserted else { break }
            // A block split by page boundaries yields one slice per page; keep them all together before following the part link.
            for index in entryIndexesByRef[entry.ref] ?? [] where !emittedIndexes.contains(index) {
                chain.append(entries[index])
            }
            guard let nextPart = link(entry.block["nextPart"]) else { break }
            current = entryIndexesByRef[nextPart]?.first.map({ entries[$0] })
        }
        return chain
    }

    private static func entrySeparator(previous: Entry, current: Entry) -> [UInt16] {
        if sameBlockSlicesTouch(previous: previous, current: current) {
            return []
        }
        if arePartNeighbors(previous: previous, current: current) {
            return SDTContent.partBoundarySeparator(previousBlock: previous.block, nextBlock: current.block)
        }
        if previous.ref == current.ref || previous.ref.first != current.ref.first {
            return Array("\n\n".utf16)
        }
        return Array("\n".utf16)
    }

    private static func sameBlockSlicesTouch(previous: Entry, current: Entry) -> Bool {
        return SDTContent.sameRef(previous.ref, current.ref)
            && (samePoint(previous.endPoint, current.startPoint) || samePoint(current.endPoint, previous.startPoint))
    }

    private static func arePartNeighbors(previous: Entry, current: Entry) -> Bool {
        return SDTContent.sameRef(link(previous.block["nextPart"]), current.ref)
            || SDTContent.sameRef(link(current.block["previousPart"]), previous.ref)
            || SDTContent.sameRef(link(previous.block["previousPart"]), current.ref)
            || SDTContent.sameRef(link(current.block["nextPart"]), previous.ref)
    }

    private static func samePoint(_ lhs: SDTContent.Point, _ rhs: SDTContent.Point) -> Bool {
        return SDTContent.sameRef(lhs.ref, rhs.ref) && lhs.offset == rhs.offset
    }

    private static func link(_ value: Any?) -> SDTContent.Ref? {
        guard let values = value as? [Any] else { return nil }
        let ref = values.compactMap({ SDTContent.integer(from: $0) })
        return ref.count == values.count ? ref : nil
    }

    // MARK: - Block text

    private static func rangeBlockTexts(content: [Any], rangeValue: Any?) -> [Entry] {
        var entries: [Entry] = []
        SDTContent.walkContentRangeLeafBlocks(content: content, rangeValue: rangeValue) { leaf in
            guard (leaf.block["flowClass"] as? String) != "excluded" else { return }
            let text = blockRangeText(block: leaf.block, blockRef: leaf.ref, startPoint: leaf.startPoint, endPoint: leaf.endPoint)
            if !text.isEmpty {
                entries.append(Entry(index: 0, ref: leaf.ref, block: leaf.block, text: text, startPoint: leaf.startPoint, endPoint: leaf.endPoint))
            }
        }
        return entries
    }

    private static func blockRangeText(block: SDTContent.Node, blockRef: SDTContent.Ref, startPoint: SDTContent.Point, endPoint: SDTContent.Point) -> [UInt16] {
        let segments = plainTextSegments(of: block, ref: blockRef)
        guard segments.contains(where: { $0.isText }) else { return [] }

        let blockStartPoint = point(startPoint, inBlock: blockRef)
        let blockEndPoint = point(endPoint, inBlock: blockRef)
        let startIndex = blockStartPoint.map({ startSegmentIndex(in: segments, point: $0) }) ?? segments.firstIndex(where: { $0.isText }) ?? -1
        let endIndex = blockEndPoint.map({ endSegmentIndex(in: segments, point: $0) }) ?? segments.lastIndex(where: { $0.isText }) ?? -1
        guard startIndex != -1, endIndex != -1, startIndex <= endIndex else { return [] }

        var parts: [[UInt16]] = []
        var pendingSeparator: [UInt16] = []
        for index in startIndex...endIndex {
            switch segments[index] {
            case .separator(let text):
                pendingSeparator += text

            case .text(let ref, let text):
                let rangeText = segmentRangeText(ref: ref, text: text, startPoint: index == startIndex ? blockStartPoint : nil, endPoint: index == endIndex ? blockEndPoint : nil)
                guard !rangeText.isEmpty else { continue }
                if !parts.isEmpty && !pendingSeparator.isEmpty {
                    parts.append(pendingSeparator)
                }
                pendingSeparator = []
                parts.append(rangeText)
            }
        }
        return parts.flatMap({ $0 })
    }

    private static func point(_ point: SDTContent.Point, inBlock blockRef: SDTContent.Ref) -> SDTContent.Point? {
        guard let ref = point.ref, blockRef.count <= ref.count, Array(ref.prefix(blockRef.count)) == blockRef else { return nil }
        return point
    }

    private static func plainTextSegments(of node: SDTContent.Node, ref: SDTContent.Ref) -> [PlainTextSegment] {
        if let text = SDTContent.text(of: node) {
            return [.text(ref: ref, text: text)]
        }
        guard let content = node["content"] as? [Any] else { return [] }

        let hasChildBlock = content.contains(where: { ($0 as? SDTContent.Node).map({ !SDTContent.isTextNode($0) }) ?? false })
        if !hasChildBlock {
            return content.enumerated().compactMap({ index, child in
                SDTContent.text(of: child as? SDTContent.Node).map({ .text(ref: ref + [index], text: $0) })
            })
        }

        var segments: [PlainTextSegment] = []
        for (index, child) in content.enumerated() {
            guard let child = child as? SDTContent.Node, !SDTContent.isTextNode(child) else { continue }
            let childSegments = plainTextSegments(of: child, ref: ref + [index])
            guard !childSegments.isEmpty else { continue }
            if !segments.isEmpty {
                segments.append(.separator(Array("\n".utf16)))
            }
            segments += childSegments
        }
        return segments
    }

    private static func segmentRangeText(ref: SDTContent.Ref, text: [UInt16], startPoint: SDTContent.Point?, endPoint: SDTContent.Point?) -> [UInt16] {
        let length = text.count
        guard length > 0 else { return [] }
        var startOffset = (SDTContent.sameRef(startPoint?.ref, ref) ? startPoint?.offset : nil) ?? 0
        var endOffset = (SDTContent.sameRef(endPoint?.ref, ref) ? endPoint?.offset : nil) ?? length
        startOffset = max(0, min(startOffset, length))
        endOffset = max(0, min(endOffset, length))
        guard endOffset > startOffset else { return [] }
        return Array(text[startOffset..<endOffset])
    }

    private static func startSegmentIndex(in segments: [PlainTextSegment], point: SDTContent.Point) -> Int {
        if point.offset != nil {
            return exactTextSegmentIndex(in: segments, ref: point.ref)
        }
        guard let pointRef = point.ref else { return -1 }
        return segments.firstIndex(where: { segment in
            guard case .text(let ref, _) = segment else { return false }
            return SDTContent.compareRefs(ref, pointRef) >= 0
        }) ?? -1
    }

    private static func endSegmentIndex(in segments: [PlainTextSegment], point: SDTContent.Point) -> Int {
        if point.offset != nil {
            return exactTextSegmentIndex(in: segments, ref: point.ref)
        }
        guard let pointRef = point.ref else { return -1 }
        for (index, segment) in segments.enumerated() {
            guard case .text(let ref, _) = segment, SDTContent.compareRefs(ref, pointRef) >= 0 else { continue }
            return segments[..<index].lastIndex(where: { $0.isText }) ?? -1
        }
        return segments.lastIndex(where: { $0.isText }) ?? -1
    }

    private static func exactTextSegmentIndex(in segments: [PlainTextSegment], ref: SDTContent.Ref?) -> Int {
        return segments.firstIndex(where: { segment in
            guard case .text(let segmentRef, _) = segment else { return false }
            return SDTContent.sameRef(segmentRef, ref)
        }) ?? -1
    }

    // MARK: - Output

    /// JavaScript `replace(/[ \t]+$/gm, '')`: drops spaces and tabs before every line terminator and at the end.
    private static func removingTrailingSpacesAndTabsOfLines(in units: [UInt16]) -> [UInt16] {
        var result: [UInt16] = []
        var pending: [UInt16] = []
        for unit in units {
            switch unit {
            case 0x20, 0x09:
                pending.append(unit)

            case 0x0A, 0x0D, 0x2028, 0x2029:
                pending = []
                result.append(unit)

            default:
                result += pending
                pending = []
                result.append(unit)
            }
        }
        return result
    }

    /// JavaScript `trim()`.
    private static func trimmed(_ units: [UInt16]) -> [UInt16] {
        guard let start = units.firstIndex(where: { !SDTContent.isWhitespace($0) }), let end = units.lastIndex(where: { !SDTContent.isWhitespace($0) }) else { return [] }
        return Array(units[start...end])
    }
}
