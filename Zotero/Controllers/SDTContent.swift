//
//  SDTContent.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 21.10.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

/// Native port of the structured document text content-tree helpers that read aloud needs, from `zotero/structured-document-text`
/// (`src/range.js` and `src/parts.js`): content ranges and points, leaf block walking, and part chains (logical paragraphs
/// split across pages or columns).
///
/// Works on the materialized structure as decoded by `JSONSerialization`. Text is handled in UTF-16 code units, like the
/// JavaScript implementation, so that offsets and positions match it exactly.
enum SDTContent {
    typealias Node = [String: Any]
    typealias Ref = [Int]

    /// A content point split into the ref of the node it points to and, when it points into a text node, the offset in it.
    struct Point {
        let ref: Ref?
        let offset: Int?
    }

    struct LeafBlock {
        let block: Node
        let ref: Ref
        let startPoint: Point
        let endPoint: Point
    }

    struct Part {
        let ref: Ref
        let block: Node
    }

    // MARK: - Refs

    static func compareRefs(_ lhs: Ref, _ rhs: Ref) -> Int {
        for index in 0..<min(lhs.count, rhs.count) where lhs[index] != rhs[index] {
            return lhs[index] - rhs[index]
        }
        return lhs.count - rhs.count
    }

    static func sameRef(_ lhs: Ref?, _ rhs: Ref?) -> Bool {
        guard let lhs, let rhs else { return false }
        return lhs == rhs
    }

    static func refKey(_ ref: Ref) -> String {
        return ref.map(String.init).joined(separator: ",")
    }

    // MARK: - Nodes

    static func isTextNode(_ node: Any?) -> Bool {
        return (node as? Node)?["text"] is String
    }

    static func isLeafBlock(_ node: Node) -> Bool {
        guard !isTextNode(node) else { return false }
        guard let content = node["content"] as? [Any], !content.isEmpty else { return true }
        return !content.contains(where: { isBlockChild($0) })
    }

    static func text(of node: Node?) -> [UInt16]? {
        return (node?["text"] as? String).flatMap { Array($0.utf16) }
    }

    static func node(at ref: Ref, in structure: Node) -> Node? {
        var content = structure["content"] as? [Any]
        var node: Node?
        for index in ref {
            guard let children = content, index >= 0, index < children.count, let child = children[index] as? Node else { return nil }
            node = child
            content = child["content"] as? [Any]
        }
        return node
    }

    /// A non-text child counts as a block; JavaScript skips falsy children, which `JSONSerialization` decodes as `NSNull`.
    private static func isBlockChild(_ child: Any) -> Bool {
        guard let child = child as? Node else { return false }
        return !isTextNode(child)
    }

    private static func firstTextNode(in node: Node?) -> Node? {
        guard let node else { return nil }
        if isTextNode(node) {
            return node
        }
        for child in (node["content"] as? [Any]) ?? [] {
            if let textNode = firstTextNode(in: child as? Node) {
                return textNode
            }
        }
        return nil
    }

    private static func lastTextNode(in node: Node?) -> Node? {
        guard let node else { return nil }
        if isTextNode(node) {
            return node
        }
        for child in ((node["content"] as? [Any]) ?? []).reversed() {
            if let textNode = lastTextNode(in: child as? Node) {
                return textNode
            }
        }
        return nil
    }

    // MARK: - Content ranges

    /// Returns `value` as a content boundary: a non-empty array of non-negative integers.
    static func contentBoundary(from value: Any?) -> Ref? {
        guard let values = value as? [Any], !values.isEmpty else { return nil }
        var boundary: Ref = []
        for value in values {
            guard let index = integer(from: value), index >= 0 else { return nil }
            boundary.append(index)
        }
        return boundary
    }

    static func contentRange(from value: Any?) -> (start: Ref, end: Ref)? {
        guard let values = value as? [Any], values.count == 2, let start = contentBoundary(from: values[0]), let end = contentBoundary(from: values[1]) else { return nil }
        return (start, end)
    }

    static func splitContentPoint(_ point: Ref, content: [Any]) -> Point {
        var ref: Ref = []
        var node: Any?
        for (index, value) in point.enumerated() {
            if isTextNode(node) && index == point.count - 1 {
                return Point(ref: ref, offset: value)
            }
            ref.append(value)
            if ref.count == 1 {
                node = value < content.count ? content[value] : nil
            } else if let children = (node as? Node)?["content"] as? [Any] {
                node = value < children.count ? children[value] : nil
            } else {
                node = nil
            }
        }
        return Point(ref: ref, offset: nil)
    }

    /// Calls `callback` for every leaf block (a block whose children are all text nodes) that intersects `range`, in
    /// document order. `range` is a content range value as stored in the structure (e.g. a page's `contentRange`).
    static func walkContentRangeLeafBlocks(content: [Any], rangeValue: Any?, callback: (LeafBlock) -> Void) {
        guard let range = contentRange(from: rangeValue) else { return }
        walkContentRangeLeafBlocks(content: content, range: range, callback: callback)
    }

    static func walkContentRangeLeafBlocks(content: [Any], range: (start: Ref, end: Ref), callback: (LeafBlock) -> Void) {
        guard !range.start.isEmpty, !range.end.isEmpty, let span = contentRangeBlockSpan(range: range, topLevelBlockCount: content.count), span.start < span.endExclusive else { return }
        let startPoint = splitContentPoint(range.start, content: content)
        let endPoint = splitContentPoint(range.end, content: content)

        for index in span.start..<span.endExclusive {
            guard let block = content[index] as? Node, !isTextNode(block) else { continue }
            walkLeafBlocks(block: block, ref: [index], range: range, startPoint: startPoint, endPoint: endPoint, callback: callback)
        }

        func walkLeafBlocks(block: Node, ref: Ref, range: (start: Ref, end: Ref), startPoint: Point, endPoint: Point, callback: (LeafBlock) -> Void) {
            if isLeafBlock(block) {
                var leafEnd = ref
                leafEnd[leafEnd.count - 1] += 1
                if compareRefs(leafEnd, range.start) <= 0 || compareRefs(ref, range.end) >= 0 {
                    return
                }
                callback(LeafBlock(block: block, ref: ref, startPoint: startPoint, endPoint: endPoint))
                return
            }
            for (index, child) in ((block["content"] as? [Any]) ?? []).enumerated() {
                guard let child = child as? Node, !isTextNode(child) else { continue }
                walkLeafBlocks(block: child, ref: ref + [index], range: range, startPoint: startPoint, endPoint: endPoint, callback: callback)
            }
        }
    }

    private static func contentRangeBlockSpan(range: (start: Ref, end: Ref), topLevelBlockCount: Int) -> (start: Int, endExclusive: Int)? {
        let start = range.start[0]
        guard start <= topLevelBlockCount else { return nil }
        if range.start == range.end {
            return (start, start)
        }
        let end = range.end[0]
        guard end <= topLevelBlockCount else { return nil }
        let endExclusive = end == topLevelBlockCount ? topLevelBlockCount : (range.end.count == 1 ? end : end + 1)
        return (start, max(start, endExclusive))
    }

    // MARK: - Parts

    /// Blocks of the logical paragraph `ref` belongs to, following `previousPart` to its first part and then `nextPart`.
    /// Stops at the first part `include` rejects.
    static func partChain(in structure: Node, ref: Ref, include: ((Ref, Node) -> Bool)? = nil) -> [Part] {
        guard let root = partRoot(in: structure, ref: ref) else { return [] }
        var chain: [Part] = []
        var seen: Set<String> = []
        var currentRef: Ref? = root
        while let ref = currentRef {
            guard seen.insert(refKey(ref)).inserted, let block = node(at: ref, in: structure) else { break }
            if let include, !include(ref, block) {
                break
            }
            chain.append(Part(ref: ref, block: block))
            currentRef = contentBoundary(fromPartLink: block["nextPart"])
        }
        return chain

        func partRoot(in structure: Node, ref: Ref) -> Ref? {
            var currentRef = ref
            var seen: Set<String> = []
            while true {
                guard seen.insert(refKey(currentRef)).inserted else { return currentRef }
                guard let link = node(at: currentRef, in: structure)?["previousPart"] as? [Any] else { return currentRef }
                // A malformed link can't be resolved to a node, which JavaScript turns into an empty chain.
                guard let previous = contentBoundary(fromPartLink: link) else { return nil }
                currentRef = previous
            }
        }
    }

    /// Whether a hard hyphen ending `previousBlock` joins a word continued in lowercase at the start of `nextBlock`.
    static func shouldDropHardHyphenAtPartBoundary(previousBlock: Node, nextBlock: Node) -> Bool {
        guard let lastText = text(of: lastTextNode(in: previousBlock)), lastText.last == hyphen, let firstChar = text(of: firstTextNode(in: nextBlock))?.first else { return false }
        return firstChar >= lowercaseA && firstChar <= lowercaseZ
    }

    /// Separator inserted between two parts of a logical paragraph: a space between two words, nothing otherwise.
    static func partBoundarySeparator(previousBlock: Node, nextBlock: Node) -> [UInt16] {
        guard let lastNode = lastTextNode(in: previousBlock), let firstNode = firstTextNode(in: nextBlock), let lastText = text(of: lastNode), let firstText = text(of: firstNode) else { return [] }
        if lastText.last.flatMap(isWhitespace) == true || firstText.first.flatMap(isWhitespace) == true {
            return []
        }
        if textNodeEndsWithSoftHyphen(lastNode) {
            return []
        }
        if isLetterOrNumber(lastScalarOf: lastText) && isLetterOrNumber(firstScalarOf: firstText) {
            return [space]
        }
        return []
    }

    /// Part links are refs, but unlike content boundaries they aren't required to be non-negative.
    private static func contentBoundary(fromPartLink value: Any?) -> Ref? {
        guard let values = value as? [Any] else { return nil }
        var ref: Ref = []
        for value in values {
            guard let index = integer(from: value) else { return nil }
            ref.append(index)
        }
        return ref
    }

    /// Whether the PDF text map of `node` marks its last character as a soft hyphen (header bit 0 of the last run).
    private static func textNodeEndsWithSoftHyphen(_ node: Node) -> Bool {
        guard let textMap = (node["anchor"] as? Node)?["textMap"] as? String,
              let data = textMap.data(using: .utf8),
              let runs = (try? JSONSerialization.jsonObject(with: data)) as? [Any],
              let lastRun = runs.last as? [Any],
              let header = lastRun.first as? NSNumber
        else { return false }
        return header.int32Value & 1 != 0
    }

    // MARK: - Characters

    static let space: UInt16 = 0x20
    static let hyphen: UInt16 = 0x2D
    private static let lowercaseA: UInt16 = 0x61
    private static let lowercaseZ: UInt16 = 0x7A

    /// JavaScript `\s`: white space and line terminators.
    static func isWhitespace(_ unit: UInt16) -> Bool {
        switch unit {
        case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF:
            return true

        default:
            return false
        }
    }

    static func containsNonWhitespace<C: Swift.Collection>(_ units: C) -> Bool where C.Element == UInt16 {
        return units.contains(where: { !isWhitespace($0) })
    }

    /// JavaScript `/[\p{L}\p{N}]$/u`: whether the last code point is a letter or a number.
    private static func isLetterOrNumber(lastScalarOf units: [UInt16]) -> Bool {
        guard let last = units.last else { return false }
        if UTF16.isTrailSurrogate(last), units.count > 1, UTF16.isLeadSurrogate(units[units.count - 2]) {
            return isLetterOrNumber(Unicode.Scalar(UInt32(0x10000) + (UInt32(units[units.count - 2] - 0xD800) << 10) + UInt32(last - 0xDC00)))
        }
        return isLetterOrNumber(Unicode.Scalar(last))
    }

    /// JavaScript `/^[\p{L}\p{N}]/u`: whether the first code point is a letter or a number.
    private static func isLetterOrNumber(firstScalarOf units: [UInt16]) -> Bool {
        guard let first = units.first else { return false }
        if UTF16.isLeadSurrogate(first), units.count > 1, UTF16.isTrailSurrogate(units[1]) {
            return isLetterOrNumber(Unicode.Scalar(UInt32(0x10000) + (UInt32(first - 0xD800) << 10) + UInt32(units[1] - 0xDC00)))
        }
        return isLetterOrNumber(Unicode.Scalar(first))
    }

    private static func isLetterOrNumber(_ scalar: Unicode.Scalar?) -> Bool {
        guard let scalar else { return false }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter, .decimalNumber, .letterNumber, .otherNumber:
            return true

        default:
            return false
        }
    }

    // MARK: - Values

    /// JavaScript `Number.isInteger`: an integral number that isn't a boolean.
    static func integer(from value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double.isFinite, double.rounded() == double else { return nil }
        return number.intValue
    }

    /// JavaScript truthiness of a decoded JSON value.
    static func isTruthy(_ value: Any?) -> Bool {
        switch value {
        case .none, is NSNull:
            return false

        case let number as NSNumber:
            return number.doubleValue != 0 && !number.doubleValue.isNaN

        case let string as String:
            return !string.isEmpty

        default:
            return true
        }
    }
}
