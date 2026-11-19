//
//  SDTPositionMapper.swift
//  Zotero
//
//  Created by Michal Rentka on 04.11.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

/// Converts between SDT positions and the reader's source positions (an EPUB CFI `FragmentSelector`, a snapshot `CssSelector`
/// or `TextPositionSelector`) natively, so that read aloud resumes and stores positions the same way in the reader and without it
/// (CarPlay). Positions are resolved purely from the anchors stored in the structured document text (`selectorMap`, `stream`,
/// `deltaMap` and `catalog.domMap`), the same way the reader does.
///
/// Native port of the reader's position mappers. Keep in sync with (paths relative to the `reader` submodule):
/// - `src/common/sdt/position-mapper.ts` (`getTextNodeSpans`)
/// - `src/common/sdt/epub-position-mapper.ts` (`EPUBPositionMapper`)
/// - `src/common/sdt/snapshot-position-mapper.ts` (`SnapshotPositionMapper`)
/// - `src/common/sdt/deltamap-invert.ts` (`localOriginalToNFC`)
/// - `src/common/view.js` (`sourceToSDTPosition`, which passes SDT positions through)
/// - `structured-document-text/src/dom/deltamap.js`
/// - `structured-document-text/src/dom/epub/decode.js`
/// - `structured-document-text/src/dom/snapshot/dommap.js`
///
/// PDF isn't covered, read aloud stores PDF positions as page rects (`ReadAloudResumePosition.pdf`) instead.
///
/// Text offsets are in UTF-16 code units, like the JavaScript implementation. Immutable once created, so it can be created on a
/// background queue and used on another one.
final class SDTPositionMapper {
    private enum Mapper {
        case epub(EPUBPositionMapper)
        case snapshot(SnapshotPositionMapper)
    }

    private let mapper: Mapper

    /// Returns `nil` for documents other than EPUB and snapshots. See `createPositionMapper` in the reader
    /// (`src/common/sdt/create-position-mapper.ts`).
    init?(structure: SDTContent.Node) {
        let processor = (structure["metadata"] as? SDTContent.Node)?["processor"] as? SDTContent.Node
        switch processor?["type"] as? String {
        case "epub":
            mapper = .epub(EPUBPositionMapper(structure: structure))

        case "snapshot":
            mapper = .snapshot(SnapshotPositionMapper(structure: structure))

        default:
            return nil
        }
    }

    /// The reader's source position covering `position`, or `nil` if it can't be mapped. Port of `sdtToSourcePosition`.
    func sourcePosition(for position: SDTPosition) -> ReaderSourcePosition? {
        switch mapper {
        case .epub(let mapper):
            return mapper.sourcePosition(for: position)

        case .snapshot(let mapper):
            return mapper.sourcePosition(for: position)
        }
    }

    /// The SDT position of a reader source position, or `nil` if it can't be mapped. SDT positions (stored by Reading Mode) are
    /// returned as they are. Port of `sourceToSDTPosition` (`src/common/view.js` and the mappers).
    func sdtPosition(for source: ReaderSourcePosition) -> SDTPosition? {
        if let start = SDTContent.contentBoundary(from: source["start"]), let end = SDTContent.contentBoundary(from: source["end"]) {
            return SDTPosition(start: start, end: end)
        }
        switch mapper {
        case .epub(let mapper):
            return mapper.sdtPosition(for: source)

        case .snapshot(let mapper):
            return mapper.sdtPosition(for: source)
        }
    }
}

// MARK: - Text node spans

/// One text node's intersection with an SDT position: characters `[start, end)` of `node` are covered. Port of `TextNodeSpan`
/// (`src/common/sdt/position-mapper.ts`).
private struct SDTTextNodeSpan {
    let block: SDTContent.Node
    let node: SDTContent.Node
    let ref: SDTContent.Ref
    let start: Int
    let end: Int

    /// The text node spans covered by `position`, in document order. Port of `getTextNodeSpans`
    /// (`src/common/sdt/position-mapper.ts`).
    static func spans(in content: [Any], position: SDTPosition) -> [SDTTextNodeSpan] {
        var spans: [SDTTextNodeSpan] = []
        SDTContent.walkContentRangeLeafBlocks(content: content, range: (position.start, position.end)) { leaf in
            guard let nodes = leaf.block["content"] as? [Any] else { return }
            for (index, value) in nodes.enumerated() {
                guard let node = value as? SDTContent.Node, let text = node["text"] as? String else { continue }
                let nodeRef = leaf.ref + [index]
                var start = 0
                var end = text.utf16.count
                if let startRef = leaf.startPoint.ref {
                    let comparison = SDTContent.compareRefs(nodeRef, startRef)
                    if comparison < 0 {
                        continue
                    }
                    if comparison == 0, let offset = leaf.startPoint.offset {
                        start = offset
                    }
                }
                if let endRef = leaf.endPoint.ref {
                    let comparison = SDTContent.compareRefs(nodeRef, endRef)
                    if comparison > 0 {
                        continue
                    }
                    if comparison == 0 {
                        guard let offset = leaf.endPoint.offset else { continue }
                        end = offset
                    }
                }
                guard end > start else { continue }
                spans.append(SDTTextNodeSpan(block: leaf.block, node: node, ref: nodeRef, start: start, end: end))
            }
        }
        return spans
    }
}

// MARK: - Delta maps

/// Position mapping between NFC-normalized node text and the original DOM text. Port of `structured-document-text/src/dom/deltamap.js`
/// and of `localOriginalToNFC` (`src/common/sdt/deltamap-invert.ts`).
///
/// A delta map is a string of space-separated "nfcPos delta" pairs, where delta = nfcIdx - origIdx. When it's absent or empty,
/// positions are 1:1.
private enum SDTDeltaMap {
    private static func pairs(of deltaMap: String) -> [(position: Int, delta: Int)] {
        let parts = deltaMap.components(separatedBy: " ")
        var result: [(position: Int, delta: Int)] = []
        var index = 0
        while index < parts.count - 1 {
            result.append((jsParseInt(parts[index]) ?? 0, jsParseInt(parts[index + 1]) ?? 0))
            index += 2
        }
        return result
    }

    /// Port of `getDelta`.
    static func delta(_ deltaMap: String?, at nfcPosition: Int) -> Int {
        guard let deltaMap, !deltaMap.isEmpty else { return 0 }
        var delta = 0
        for pair in pairs(of: deltaMap) {
            if pair.position > nfcPosition {
                break
            }
            delta = pair.delta
        }
        return delta
    }

    /// Port of `nfcToOriginal`.
    static func nfcToOriginal(_ deltaMap: String?, _ nfcPosition: Int) -> Int {
        return nfcPosition - delta(deltaMap, at: nfcPosition)
    }

    /// Port of `nfcToOriginalLocal`: a local NFC offset within an entry starting at `entryStartNFC` to the local original offset.
    static func nfcToOriginalLocal(_ deltaMap: String?, _ entryStartNFC: Int, _ localNFCPosition: Int) -> Int {
        guard let deltaMap, !deltaMap.isEmpty else { return localNFCPosition }
        let entryDelta = delta(deltaMap, at: entryStartNFC)
        let positionDelta = delta(deltaMap, at: entryStartNFC + localNFCPosition)
        return localNFCPosition - (positionDelta - entryDelta)
    }

    /// Port of `localOriginalToNFC` (`src/common/sdt/deltamap-invert.ts`): the NFC offset within an entry corresponding to a local
    /// original offset. The delta map is monotonic, so it's a binary search.
    static func localOriginalToNFC(_ deltaMap: String?, _ entryStartNFC: Int, _ localOriginal: Int, _ maxNFC: Int) -> Int {
        guard let deltaMap, !deltaMap.isEmpty else { return max(0, min(localOriginal, maxNFC)) }
        var low = 0
        var high = maxNFC
        while low < high {
            let middle = (low + high) >> 1
            if nfcToOriginalLocal(deltaMap, entryStartNFC, middle) < localOriginal {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }
}

// MARK: - EPUB

/// EPUB selector map decoding. Port of `structured-document-text/src/dom/epub/decode.js`.
///
/// Selector maps are stored relative to their parent block's CFI path. Single entry: a CFI path suffix starting with "/".
/// Multi-entry (merged text nodes): newline-separated "charLen suffix" entries.
private enum EPUBSelectorMap {
    struct Entry {
        let length: Int
        let path: String
    }

    private static let conformsTo = "http://www.idpf.org/epub/linking/cfi/epub-cfi.html"

    /// Port of `expandSelectorMap`.
    static func expand(blockSelectorMap: String, selectorMap: String) -> String {
        if selectorMap.isEmpty {
            return blockSelectorMap
        }
        if let entries = entries(of: selectorMap) {
            return entries.map({ "\($0.length) \(blockSelectorMap)\($0.path)" }).joined(separator: "\n")
        }
        return blockSelectorMap + selectorMap
    }

    /// Port of `parseSelectorMapEntries`. Returns `nil` for single-entry selector maps.
    static func entries(of selectorMap: String) -> [Entry]? {
        if selectorMap.hasPrefix("/") {
            return nil
        }
        return selectorMap.components(separatedBy: "\n").map { line in
            guard let space = line.firstIndex(of: " ") else {
                return Entry(length: 0, path: line)
            }
            return Entry(length: jsParseInt(String(line[..<space])) ?? 0, path: String(line[line.index(after: space)...]))
        }
    }

    /// Port of `resolveSelectorMap`: a character range (NFC) to a CFI range.
    static func resolve(selectorMap: String, start: Int, end: Int, deltaMap: String?) -> ReaderSourcePosition {
        if let entries = entries(of: selectorMap) {
            return resolveMultiEntry(entries: entries, start: start, end: end, deltaMap: deltaMap)
        }
        let originalStart = SDTDeltaMap.nfcToOriginal(deltaMap, start)
        let originalEnd = SDTDeltaMap.nfcToOriginal(deltaMap, end)
        if originalEnd == originalStart + 1 {
            return selector("epubcfi(\(selectorMap):\(originalStart))")
        }
        return selector("epubcfi(\(selectorMap),:\(originalStart),:\(originalEnd))")
    }

    /// Port of `resolveMultiEntry`.
    private static func resolveMultiEntry(entries: [Entry], start: Int, end: Int, deltaMap: String?) -> ReaderSourcePosition {
        let startEntry = entryWithCumulative(in: entries, at: start)
        let endEntry = entryWithCumulative(in: entries, at: end - 1)
        let originalStartLocal = SDTDeltaMap.nfcToOriginalLocal(deltaMap, startEntry.cumulative, startEntry.local)
        let originalEndLocal = SDTDeltaMap.nfcToOriginalLocal(deltaMap, endEntry.cumulative, endEntry.local) + 1

        if startEntry.path == endEntry.path {
            if originalEndLocal == originalStartLocal + 1 {
                return selector("epubcfi(\(startEntry.path):\(originalStartLocal))")
            }
            return selector("epubcfi(\(startEntry.path),:\(originalStartLocal),:\(originalEndLocal))")
        }
        return resolveRange(startSelectorMap: startEntry.path, startOffset: originalStartLocal, endSelectorMap: endEntry.path, endOffset: originalEndLocal)
    }

    /// Port of `findEntryAtWithCumulative`.
    private static func entryWithCumulative(in entries: [Entry], at offset: Int) -> (path: String, local: Int, cumulative: Int) {
        var cumulative = 0
        for entry in entries {
            if offset < cumulative + entry.length {
                return (entry.path, offset - cumulative, cumulative)
            }
            cumulative += entry.length
        }
        guard let last = entries.last else { return ("", 0, 0) }
        return (last.path, last.length, cumulative - last.length)
    }

    /// Port of `findCommonCFIPath`: the longest common step prefix of two CFI paths.
    private static func commonPath(_ lhs: String, _ rhs: String) -> (common: String, lhsRemainder: String, rhsRemainder: String) {
        if lhs == rhs {
            return (lhs, "", "")
        }
        let lhsSteps = steps(of: lhs)
        let rhsSteps = steps(of: rhs)
        var commonCount = 0
        for index in 0..<min(lhsSteps.count, rhsSteps.count) {
            if lhsSteps[index] != rhsSteps[index] {
                break
            }
            commonCount = index + 1
        }
        return (lhsSteps[..<commonCount].joined(), lhsSteps[commonCount...].joined(), rhsSteps[commonCount...].joined())

        /// Steps of a CFI path, each starting with "/" (`/\/[^/]*/g` in JavaScript). Anything before the first "/" is dropped.
        func steps(of path: String) -> [String] {
            var steps: [String] = []
            for character in path {
                if character == "/" {
                    steps.append("/")
                } else if !steps.isEmpty {
                    steps[steps.count - 1].append(character)
                }
            }
            return steps
        }
    }

    /// Port of `resolveSelectorMapRange`: a cross-node character range to a CFI range.
    static func resolveRange(
        startSelectorMap: String,
        startOffset: Int,
        endSelectorMap: String,
        endOffset: Int,
        startDeltaMap: String? = nil,
        endDeltaMap: String? = nil
    ) -> ReaderSourcePosition {
        if startSelectorMap == endSelectorMap {
            return resolve(selectorMap: startSelectorMap, start: startOffset, end: endOffset, deltaMap: startDeltaMap)
        }
        let start = resolveOnePoint(selectorMap: startSelectorMap, offset: startOffset, deltaMap: startDeltaMap)
        let end = resolveOnePoint(selectorMap: endSelectorMap, offset: endOffset, deltaMap: endDeltaMap)

        if start.path == end.path {
            return selector("epubcfi(\(start.path),:\(start.offset),:\(end.offset))")
        }
        let (common, startRemainder, endRemainder) = commonPath(start.path, end.path)
        return selector("epubcfi(\(common),\(startRemainder):\(start.offset),\(endRemainder):\(end.offset))")
    }

    /// Port of `resolveOnePoint`.
    private static func resolveOnePoint(selectorMap: String, offset: Int, deltaMap: String?) -> (path: String, offset: Int) {
        if let entries = entries(of: selectorMap) {
            let entry = entryWithCumulative(in: entries, at: offset)
            return (entry.path, SDTDeltaMap.nfcToOriginalLocal(deltaMap, entry.cumulative, entry.local))
        }
        return (selectorMap, SDTDeltaMap.nfcToOriginal(deltaMap, offset))
    }

    private static func selector(_ value: String) -> ReaderSourcePosition {
        return ["type": "FragmentSelector", "conformsTo": conformsTo, "value": value]
    }
}

/// Port of `EPUBPositionMapper` (`src/common/sdt/epub-position-mapper.ts`).
private final class EPUBPositionMapper {
    /// One DOM text node (CFI path) covered by an SDT text node. Multi-entry selector maps (merged adjacent DOM text nodes)
    /// produce one entry per sub-path.
    private struct PathEntry {
        let ref: SDTContent.Ref
        /// Assertion-stripped absolute CFI path of the DOM text node.
        let path: String
        /// Start of this sub-path's characters within the SDT text node (NFC).
        let nodeCharStart: Int
        /// NFC length of this sub-path's characters.
        let length: Int
        let deltaMap: String?
    }

    private struct BlockEntry {
        let ref: SDTContent.Ref
        let path: String
    }

    private let content: [Any]
    private let pathEntries: [PathEntry]
    private let blockEntries: [BlockEntry]

    /// Port of the constructor and `_buildIndex`.
    init(structure: SDTContent.Node) {
        let content = (structure["content"] as? [Any]) ?? []
        var pathEntries: [PathEntry] = []
        var blockEntries: [BlockEntry] = []

        SDTContent.walkContentRangeLeafBlocks(content: content, range: ([0], [content.count])) { leaf in
            guard let blockSelectorMap = (leaf.block["anchor"] as? SDTContent.Node)?["selectorMap"] as? String, !blockSelectorMap.isEmpty else { return }
            blockEntries.append(BlockEntry(ref: leaf.ref, path: EPUBPositionMapper.stripAssertions(blockSelectorMap)))

            guard let nodes = leaf.block["content"] as? [Any] else { return }
            for (index, value) in nodes.enumerated() {
                guard let node = value as? SDTContent.Node,
                      let text = node["text"] as? String,
                      let textAnchor = node["anchor"] as? SDTContent.Node,
                      let selectorMap = textAnchor["selectorMap"] as? String
                else { continue }
                let deltaMap = textAnchor["deltaMap"] as? String
                let expanded = EPUBSelectorMap.expand(blockSelectorMap: blockSelectorMap, selectorMap: selectorMap)
                let nodeRef = leaf.ref + [index]
                if let entries = EPUBSelectorMap.entries(of: expanded) {
                    var cumulative = 0
                    for entry in entries {
                        pathEntries.append(PathEntry(ref: nodeRef, path: EPUBPositionMapper.stripAssertions(entry.path), nodeCharStart: cumulative, length: entry.length, deltaMap: deltaMap))
                        cumulative += entry.length
                    }
                } else {
                    pathEntries.append(PathEntry(ref: nodeRef, path: EPUBPositionMapper.stripAssertions(expanded), nodeCharStart: 0, length: text.utf16.count, deltaMap: deltaMap))
                }
            }
        }

        self.content = content
        self.pathEntries = pathEntries
        self.blockEntries = blockEntries
    }

    /// Port of `sdtToSourcePosition` and `textNodeSpansToSourcePosition`.
    func sourcePosition(for position: SDTPosition) -> ReaderSourcePosition? {
        let spans = SDTTextNodeSpan.spans(in: content, position: position)
        guard let first = spans.first, let last = spans.last, let startMap = expandedSelectorMap(of: first), let endMap = expandedSelectorMap(of: last) else { return nil }
        let startDeltaMap = (first.node["anchor"] as? SDTContent.Node)?["deltaMap"] as? String
        let endDeltaMap = (last.node["anchor"] as? SDTContent.Node)?["deltaMap"] as? String
        if spans.count == 1 {
            return EPUBSelectorMap.resolve(selectorMap: startMap, start: first.start, end: first.end, deltaMap: startDeltaMap)
        }
        return EPUBSelectorMap.resolveRange(
            startSelectorMap: startMap,
            startOffset: first.start,
            endSelectorMap: endMap,
            endOffset: last.end,
            startDeltaMap: startDeltaMap,
            endDeltaMap: endDeltaMap
        )
    }

    /// Port of `sourceToSDTPosition`.
    func sdtPosition(for source: ReaderSourcePosition) -> SDTPosition? {
        guard source["type"] as? String == "FragmentSelector",
              let value = source["value"] as? String,
              let range = Self.parseCFIRange(value),
              let start = contentPoint(path: range.startPath, offset: range.startOffset, isEnd: false),
              let end = contentPoint(path: range.endPath, offset: range.endOffset, isEnd: true)
        else { return nil }
        return SDTPosition(start: start, end: end)
    }

    /// Port of `_pointToContentPoint`: one CFI point to an SDT content point. Tries text node paths first, then falls back to
    /// block boundaries.
    private func contentPoint(path: String, offset: Int?, isEnd: Bool) -> SDTContent.Ref? {
        let strippedPath = EPUBPositionMapper.stripAssertions(path)

        for entry in pathEntries where entry.path == strippedPath {
            // CFI offsets are in original (DOM) space, SDT text is NFC.
            let localOffset: Int
            if let offset {
                localOffset = SDTDeltaMap.localOriginalToNFC(entry.deltaMap, entry.nodeCharStart, offset, entry.length)
            } else {
                localOffset = isEnd ? entry.length : 0
            }
            return entry.ref + [entry.nodeCharStart + localOffset]
        }

        for entry in blockEntries where Self.cfiPath(strippedPath, startsWith: entry.path) {
            if isEnd {
                var end = entry.ref
                end[end.count - 1] += 1
                return end
            }
            return entry.ref
        }

        return nil
    }

    /// Port of `_getExpandedSelectorMap`.
    private func expandedSelectorMap(of span: SDTTextNodeSpan) -> String? {
        guard let blockSelectorMap = (span.block["anchor"] as? SDTContent.Node)?["selectorMap"] as? String,
              !blockSelectorMap.isEmpty,
              let selectorMap = (span.node["anchor"] as? SDTContent.Node)?["selectorMap"] as? String
        else { return nil }
        return EPUBSelectorMap.expand(blockSelectorMap: blockSelectorMap, selectorMap: selectorMap)
    }

    /// Port of `stripAssertions`: removes `[...]` assertions from a CFI path.
    private static func stripAssertions(_ path: String) -> String {
        return path.replacingOccurrences(of: "\\[[^\\]]*\\]", with: "", options: .regularExpression)
    }

    /// Port of `cfiPathStartsWith`: whether `path` continues into `prefix` at a step boundary (or matches it exactly).
    private static func cfiPath(_ path: String, startsWith prefix: String) -> Bool {
        let pathUnits = Array(path.utf16)
        let prefixUnits = Array(prefix.utf16)
        guard pathUnits.starts(with: prefixUnits) else { return false }
        guard prefixUnits.count < pathUnits.count else { return true }
        // "/", ":" or "!"
        return [0x2F, 0x3A, 0x21].contains(pathUnits[prefixUnits.count])
    }

    /// Port of `parseCFIRange`: an `epubcfi(...)` string to start/end paths with optional character offsets. Single-point CFIs
    /// produce identical start and end paths.
    private static func parseCFIRange(_ value: String) -> (startPath: String, startOffset: Int?, endPath: String, endOffset: Int?)? {
        guard let inner = firstMatch(of: "^epubcfi\\((.*)\\)$", in: value)?[1] else { return nil }
        let parts = splitTopLevel(inner)
        let startRaw: String
        let endRaw: String
        switch parts.count {
        case 3:
            startRaw = parts[0] + parts[1]
            endRaw = parts[0] + parts[2]

        case 1:
            startRaw = parts[0]
            endRaw = parts[0]

        default:
            return nil
        }
        let start = splitOffset(startRaw)
        let end = splitOffset(endRaw)
        return (start.path, start.offset, end.path, end.offset)

        /// Port of `splitTopLevel`: splits on top-level commas, ignoring commas inside `[assertions]`.
        func splitTopLevel(_ value: String) -> [String] {
            var parts: [String] = []
            var depth = 0
            var current = ""
            for scalar in value.unicodeScalars {
                if scalar == "[" {
                    depth += 1
                } else if scalar == "]" {
                    depth = max(0, depth - 1)
                } else if scalar == "," && depth == 0 {
                    parts.append(current)
                    current = ""
                    continue
                }
                current.unicodeScalars.append(scalar)
            }
            parts.append(current)
            return parts
        }

        /// Port of `splitOffset`.
        func splitOffset(_ path: String) -> (path: String, offset: Int?) {
            guard let groups = firstMatch(of: "^(.*?):(\\d+)(?:\\[[^\\]]*\\])?$", in: path), let offset = Int(groups[2]) else { return (path, nil) }
            return (groups[1], offset)
        }
    }
}

// MARK: - Snapshot

/// Index over the snapshot DOM skeleton (`catalog.domMap`), port of `structured-document-text/src/dom/snapshot/dommap.js`. Allows
/// resolving and generating `CssSelector`/`TextPositionSelector` positions rooted at arbitrary ancestor elements without the
/// source DOM.
///
/// Selector grammar covered (everything the encoder and the reader's `getUniqueSelectorContaining()` produce):
///
///     selector  = anchor (' > ' segment)*
///     anchor    = '#id' | '#id + tag' | 'body' | segment
///     segment   = tag pseudo?
///     pseudo    = ':first-child' | ':first-of-type' | ':last-child' | ':last-of-type' | ':nth-child(n)'
private final class SnapshotDomMap {
    /// `DOM_MAP_*` flag bits.
    private static let firstOfType = 1
    private static let lastOfType = 2
    private static let lastChild = 4

    final class Node {
        let tag: String
        let index: Int
        let flags: Int
        let id: String?
        let previousId: String?
        let textStart: Int
        let textLength: Int
        private(set) weak var parent: Node?
        private(set) var children: [Node] = []

        init(dictionary: SDTContent.Node, parent: Node?) {
            tag = (dictionary["tag"] as? String) ?? ""
            index = SDTContent.integer(from: dictionary["index"]) ?? 0
            flags = SDTContent.integer(from: dictionary["flags"]) ?? 0
            id = dictionary["id"] as? String
            previousId = dictionary["prevId"] as? String
            textStart = SDTContent.integer(from: dictionary["textStart"]) ?? 0
            textLength = SDTContent.integer(from: dictionary["textLength"]) ?? 0
            self.parent = parent
        }

        fileprivate func append(child: Node) {
            children.append(child)
        }
    }

    private struct Segment {
        var tag: String?
        var pseudo: String?
        var n: Int?
        /// '#id' alone: the element with that id.
        var id: String?
        /// '#prevId + tag': the element after the element with that id.
        var previousId: String?
    }

    private enum Anchor {
        case body
        case id(String)
    }

    let roots: [Node]
    /// All nodes, in document order.
    private let nodes: [Node]

    /// Port of `buildDomMapIndex`.
    init?(domMap: Any?) {
        guard let domMap = domMap as? [Any], !domMap.isEmpty else { return nil }
        var nodes: [Node] = []
        var roots: [Node] = []
        for dictionary in domMap {
            guard let dictionary = dictionary as? SDTContent.Node else { continue }
            roots.append(SnapshotDomMap.build(dictionary: dictionary, parent: nil, nodes: &nodes))
        }
        self.roots = roots
        self.nodes = nodes
    }

    private static func build(dictionary: SDTContent.Node, parent: Node?, nodes: inout [Node]) -> Node {
        let node = Node(dictionary: dictionary, parent: parent)
        nodes.append(node)
        for child in (dictionary["children"] as? [Any]) ?? [] {
            guard let child = child as? SDTContent.Node else { continue }
            node.append(child: build(dictionary: child, parent: node, nodes: &nodes))
        }
        return node
    }

    /// Port of `findDomMapContaining`: the deepest node whose subtree text contains `[start, end)` of the body text stream. `nil`
    /// when only `<body>` itself contains the range.
    func deepestNode(containingStart start: Int, end: Int) -> Node? {
        var result: Node?
        var candidates = roots
        while let next = candidates.first(where: { $0.textStart <= start && end <= $0.textStart + $0.textLength }) {
            result = next
            candidates = next.children
        }
        return result
    }

    /// Port of `generateDomMapSelector`: walks up to `<body>`, short-circuiting at the nearest element with an id, otherwise roots
    /// the path at "body".
    static func selector(for node: Node) -> String {
        var segments: [String] = []
        var current: Node? = node
        while let node = current {
            if let id = node.id {
                segments.insert("#" + cssEscape(id), at: 0)
                return segments.joined(separator: " > ")
            }
            segments.insert(segment(for: node), at: 0)
            current = node.parent
        }
        segments.insert("body", at: 0)
        return segments.joined(separator: " > ")
    }

    /// Port of `domMapSegment`.
    private static func segment(for node: Node) -> String {
        let pseudo: String
        if node.flags & firstOfType != 0 && node.flags & lastOfType != 0 {
            // Only one of its tag among the siblings
            pseudo = ""
        } else if node.index == 0 {
            pseudo = ":first-child"
        } else if node.flags & firstOfType != 0 {
            pseudo = ":first-of-type"
        } else if node.flags & lastChild != 0 {
            pseudo = ":last-child"
        } else if node.flags & lastOfType != 0 {
            pseudo = ":last-of-type"
        } else {
            pseudo = ":nth-child(\(node.index + 1))"
        }
        return node.tag + pseudo
    }

    /// Port of `matchDomMapSelector`: the node a CSS selector refers to. `nil` when the selector is outside the supported grammar,
    /// matches nothing, or matches more than one node.
    func node(matching selector: String) -> Node? {
        guard let parsed = Self.parseSelectorPath(selector) else { return nil }
        var match: Node?
        for node in nodes where Self.matches(node, anchor: parsed.anchor, segments: parsed.segments) {
            if match != nil {
                // Ambiguous
                return nil
            }
            match = node
        }
        return match
    }

    /// Port of `parseSelectorPath`.
    private static func parseSelectorPath(_ selector: String) -> (anchor: Anchor?, segments: [Segment])? {
        var parts = selector.components(separatedBy: " > ")
        var anchor: Anchor?
        var firstSegment: Segment?
        let first = parts[0]
        if first == "body" {
            if parts.count == 1 {
                // 'body' alone never targets a skeleton node
                return nil
            }
            anchor = .body
            parts.removeFirst()
        } else if first.hasPrefix("#") {
            if let plus = first.range(of: " + ") {
                // '#prevId + tag' (reader's previous-sibling shortcut)
                guard var segment = parseSegment(String(first[plus.upperBound...])) else { return nil }
                segment.previousId = String(first[first.index(after: first.startIndex)..<plus.lowerBound])
                firstSegment = segment
            } else if parts.count == 1 {
                // '#id' alone: the target is the element with that id
                firstSegment = Segment(id: String(first.dropFirst()))
            } else {
                anchor = .id(String(first.dropFirst()))
            }
            parts.removeFirst()
        }
        var segments: [Segment] = []
        if let firstSegment {
            segments.append(firstSegment)
        }
        for part in parts {
            guard let segment = parseSegment(part) else { return nil }
            segments.append(segment)
        }
        guard !segments.isEmpty else { return nil }
        return (anchor, segments)
    }

    /// Port of `parseSegment`.
    private static func parseSegment(_ part: String) -> Segment? {
        let pattern = "^([a-zA-Z][a-zA-Z0-9-]*)(?::(first-child|first-of-type|last-child|last-of-type|nth-child\\((\\d+)\\)))?$"
        guard !part.isEmpty, let groups = firstMatch(of: pattern, in: part) else { return nil }
        var segment = Segment(tag: groups[1].lowercased())
        if !groups[2].isEmpty {
            if !groups[3].isEmpty {
                segment.pseudo = "nth-child"
                segment.n = Int(groups[3])
            } else {
                segment.pseudo = groups[2]
            }
        }
        return segment
    }

    /// Port of `matchesAt`.
    private static func matches(_ node: Node, anchor: Anchor?, segments: [Segment]) -> Bool {
        var current: Node? = node
        for segment in segments.reversed() {
            guard let node = current, matches(node, segment: segment) else { return false }
            current = node.parent
        }
        switch anchor {
        case .body:
            // The chain must start directly under <body>
            return current == nil

        case .id(let id):
            guard let nodeId = current?.id else { return false }
            return cssEscape(nodeId) == id

        case .none:
            return true
        }
    }

    /// Port of `matchesSegment`.
    private static func matches(_ node: Node, segment: Segment) -> Bool {
        if let id = segment.id {
            guard let nodeId = node.id else { return false }
            return cssEscape(nodeId) == id
        }
        guard node.tag == segment.tag else { return false }
        if let previousId = segment.previousId {
            guard let nodePreviousId = node.previousId, cssEscape(nodePreviousId) == previousId else { return false }
        }
        switch segment.pseudo {
        case .none:
            return true

        case "first-child":
            return node.index == 0

        case "first-of-type":
            return node.flags & firstOfType != 0

        case "last-child":
            return node.flags & lastChild != 0

        case "last-of-type":
            return node.flags & lastOfType != 0

        case "nth-child":
            return node.index + 1 == segment.n

        default:
            return false
        }
    }

    /// Port of `cssEscape`: `CSS.escape()` per the CSSOM spec, on UTF-16 code units like JavaScript.
    static func cssEscape(_ value: String) -> String {
        let units = Array(value.utf16)
        var result: [UInt16] = []
        let firstUnit = units.first
        for (index, unit) in units.enumerated() {
            if unit == 0 {
                result.append(0xFFFD)
                continue
            }
            if (0x0001...0x001F).contains(unit) || unit == 0x007F
                || (index == 0 && (0x0030...0x0039).contains(unit))
                || (index == 1 && (0x0030...0x0039).contains(unit) && firstUnit == 0x002D) {
                result.append(contentsOf: ("\\" + String(unit, radix: 16) + " ").utf16)
                continue
            }
            if index == 0 && units.count == 1 && unit == 0x002D {
                result.append(0x5C)
                result.append(unit)
                continue
            }
            if unit >= 0x0080 || unit == 0x002D || unit == 0x005F
                || (0x0030...0x0039).contains(unit)
                || (0x0041...0x005A).contains(unit)
                || (0x0061...0x007A).contains(unit) {
                result.append(unit)
                continue
            }
            result.append(0x5C)
            result.append(unit)
        }
        return String(decoding: result, as: UTF16.self)
    }
}

/// Port of `SnapshotPositionMapper` (`src/common/sdt/snapshot-position-mapper.ts`).
private final class SnapshotPositionMapper {
    /// One SDT text node located in the snapshot's body text stream. `stream` and `rawLength` are in raw original characters (the
    /// space WADM `TextPositionSelector`s are measured in), while the node's text is whitespace-collapsed and NFC-normalized,
    /// `deltaMap` translates between the two.
    private struct StreamEntry {
        let ref: SDTContent.Ref
        /// Body-stream offset of the node's first character.
        let stream: Int
        /// Raw character length of the node's source text.
        let rawLength: Int
        /// Length of the node's (collapsed, NFC) text.
        let nfcLength: Int
        let deltaMap: String?
        /// A text-less leaf block (e.g. an image) anchored by its block selector. Resolves to a block-level content point.
        let isBlock: Bool
    }

    private let content: [Any]
    private let domMap: SnapshotDomMap?
    /// All anchored text nodes, ordered by stream offset.
    private let entries: [StreamEntry]
    private let entriesByRef: [SDTContent.Ref: StreamEntry]

    /// Port of the constructor, `_buildIndex` and `_indexTextlessBlock`.
    init(structure: SDTContent.Node) {
        let content = (structure["content"] as? [Any]) ?? []
        let domMap = SnapshotDomMap(domMap: (structure["catalog"] as? SDTContent.Node)?["domMap"])
        var entries: [StreamEntry] = []

        SDTContent.walkContentRangeLeafBlocks(content: content, range: ([0], [content.count])) { leaf in
            var addedTextEntry = false
            for (index, value) in ((leaf.block["content"] as? [Any]) ?? []).enumerated() {
                guard let node = value as? SDTContent.Node,
                      let text = node["text"] as? String,
                      let anchor = node["anchor"] as? SDTContent.Node,
                      let stream = SDTContent.integer(from: anchor["stream"])
                else { continue }
                let deltaMap = anchor["deltaMap"] as? String
                let nfcLength = text.utf16.count
                entries.append(StreamEntry(
                    ref: leaf.ref + [index],
                    stream: stream,
                    rawLength: SDTDeltaMap.nfcToOriginalLocal(deltaMap, 0, nfcLength),
                    nfcLength: nfcLength,
                    deltaMap: deltaMap,
                    isBlock: false
                ))
                addedTextEntry = true
            }
            guard !addedTextEntry else { return }
            // Anchor a leaf block that contributes no text of its own (an image is the common case) in the body stream via its block
            // selector, so that a source position covering the block resolves to it.
            guard let selectorMap = (leaf.block["anchor"] as? SDTContent.Node)?["selectorMap"] as? String,
                  !selectorMap.isEmpty,
                  let matched = domMap?.node(matching: selectorMap)
            else { return }
            entries.append(StreamEntry(ref: leaf.ref, stream: matched.textStart, rawLength: matched.textLength, nfcLength: 0, deltaMap: nil, isBlock: true))
        }

        // Stable, like JavaScript's sort.
        let sortedEntries = entries.enumerated()
            .sorted(by: { $0.element.stream != $1.element.stream ? $0.element.stream < $1.element.stream : $0.offset < $1.offset })
            .map({ $0.element })
        var entriesByRef: [SDTContent.Ref: StreamEntry] = [:]
        for entry in entries {
            entriesByRef[entry.ref] = entry
        }

        self.content = content
        self.domMap = domMap
        self.entries = sortedEntries
        self.entriesByRef = entriesByRef
    }

    /// Port of `sdtToSourcePosition` and `textNodeSpansToSourcePosition`.
    func sourcePosition(for position: SDTPosition) -> ReaderSourcePosition? {
        var start: Int?
        var end: Int?
        for span in SDTTextNodeSpan.spans(in: content, position: position) {
            // Synthetic nodes (<br> newline, image alt text) have no source text of their own.
            guard let entry = entriesByRef[span.ref] else { continue }
            if start == nil {
                start = entry.stream + SDTDeltaMap.nfcToOriginalLocal(entry.deltaMap, 0, span.start)
            }
            end = entry.stream + SDTDeltaMap.nfcToOriginalLocal(entry.deltaMap, 0, span.end)
        }
        guard let start, let end, end > start else { return nil }
        return selector(streamStart: start, streamEnd: end)
    }

    /// Port of `sourceToSDTPosition`.
    func sdtPosition(for source: ReaderSourcePosition) -> SDTPosition? {
        guard let range = streamRange(of: source), let start = contentPoint(streamPosition: range.start, isEnd: false) else { return nil }
        let end: SDTContent.Ref? = range.end == range.start ? start : contentPoint(streamPosition: range.end, isEnd: true)
        guard let end, SDTContent.compareRefs(start, end) <= 0 else { return nil }
        return SDTPosition(start: start, end: end)
    }

    /// Port of `_streamRangeToSelector`: the deepest element containing the whole range, refined by element-relative text positions
    /// unless the range covers the element's text exactly.
    private func selector(streamStart start: Int, streamEnd end: Int) -> ReaderSourcePosition {
        guard let containing = domMap?.deepestNode(containingStart: start, end: end) else {
            // Only <body> contains the range, stream offsets are body-relative text positions already
            return ["type": "TextPositionSelector", "start": start, "end": end]
        }
        let value = SnapshotDomMap.selector(for: containing)
        if start == containing.textStart && end == containing.textStart + containing.textLength {
            return ["type": "CssSelector", "value": value]
        }
        return [
            "type": "CssSelector",
            "value": value,
            "refinedBy": ["type": "TextPositionSelector", "start": start - containing.textStart, "end": end - containing.textStart] as [String: Any]
        ]
    }

    /// Port of `_selectorToStreamRange`: handles `CssSelector`s rooted at any element in the DOM map and bare (body-relative)
    /// `TextPositionSelector`s.
    private func streamRange(of source: ReaderSourcePosition) -> (start: Int, end: Int)? {
        switch source["type"] as? String {
        case "TextPositionSelector":
            guard let start = (source["start"] as? NSNumber)?.intValue, let end = (source["end"] as? NSNumber)?.intValue else { return nil }
            return (start, end)

        case "CssSelector":
            guard let domMap, let value = source["value"] as? String, let matched = domMap.node(matching: value) else { return nil }
            if let refinedBy = source["refinedBy"] as? [String: Any], refinedBy["type"] as? String == "TextPositionSelector" {
                guard let start = (refinedBy["start"] as? NSNumber)?.intValue, let end = (refinedBy["end"] as? NSNumber)?.intValue else { return nil }
                return (matched.textStart + start, matched.textStart + end)
            }
            return (matched.textStart, matched.textStart + matched.textLength)

        default:
            return nil
        }
    }

    /// Port of `_streamPointToContentPoint`: a body-stream offset to an SDT content point, clamped into the nearest text node when
    /// the offset falls in a gap (whitespace between blocks, or text the extraction didn't keep).
    private func contentPoint(streamPosition: Int, isEnd: Bool) -> SDTContent.Ref? {
        guard let entry = isEnd ? lastEntry(startingBefore: streamPosition) : firstEntry(endingAfter: streamPosition) else { return nil }
        if entry.isBlock {
            return entry.ref
        }
        let localRaw = max(0, min(streamPosition - entry.stream, entry.rawLength))
        return entry.ref + [SDTDeltaMap.localOriginalToNFC(entry.deltaMap, 0, localRaw, entry.nfcLength)]
    }

    /// Port of `_firstEntryEndingAfter`.
    private func firstEntry(endingAfter streamPosition: Int) -> StreamEntry? {
        var low = 0
        var high = entries.count
        while low < high {
            let middle = (low + high) >> 1
            if entries[middle].stream + entries[middle].rawLength <= streamPosition {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low < entries.count ? entries[low] : nil
    }

    /// Port of `_lastEntryStartingBefore`.
    private func lastEntry(startingBefore streamPosition: Int) -> StreamEntry? {
        var low = 0
        var high = entries.count
        while low < high {
            let middle = (low + high) >> 1
            if entries[middle].stream < streamPosition {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low > 0 ? entries[low - 1] : nil
    }
}

// MARK: - Helpers

/// JavaScript `parseInt(value)` for base-10 integers: optional leading whitespace and sign, then digits, ignoring anything after.
/// `nil` where JavaScript returns `NaN`.
private func jsParseInt(_ value: String) -> Int? {
    var scalars = Substring(value).drop(while: { $0.isWhitespace })
    var sign = 1
    if let first = scalars.first, first == "-" || first == "+" {
        sign = first == "-" ? -1 : 1
        scalars = scalars.dropFirst()
    }
    let digits = scalars.prefix(while: { $0.isASCII && $0.isNumber })
    guard let number = Int(digits) else { return nil }
    return sign * number
}

/// Groups of the first match of `pattern` (with `.` matching newlines, like the JavaScript `s` flag), unmatched groups as empty
/// strings. Index 0 is the whole match.
private func firstMatch(of pattern: String, in string: String) -> [String]? {
    guard let expression = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return nil }
    let nsString = string as NSString
    guard let match = expression.firstMatch(in: string, range: NSRange(location: 0, length: nsString.length)) else { return nil }
    return (0..<match.numberOfRanges).map { index in
        let range = match.range(at: index)
        return range.location == NSNotFound ? "" : nsString.substring(with: range)
    }
}
