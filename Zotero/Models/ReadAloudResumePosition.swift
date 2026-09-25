//
//  ReadAloudResumePosition.swift
//  Zotero
//
//  Created by Michal Rentka on 24.09.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import CoreGraphics
import Foundation

/// An opaque reader source position (an EPUB CFI `FragmentSelector`, a snapshot `CssSelector`) as the reader reports it
/// for a text selection. Never interpreted here — it's handed back to the reader to be mapped to an `SDTPosition`.
typealias ReaderSourcePosition = [String: Any]

/// The sentence where read-aloud playback left off, in the representation that is stored and synced as
/// `lastReadAloudPosition_<library>_<key>`. Resuming looks that sentence up again and starts reading at its beginning,
/// so the anchor survives a re-extraction of the document and travels between devices.
enum ReadAloudResumePosition {
    /// PDF: rects of the sentence (PDF coordinate space) on the structured-document-text page it lies on.
    case pdf(pageIndex: Int, rects: [CGRect])
    /// HTML/EPUB: the reader's own source position for the sentence (an EPUB CFI `FragmentSelector`, a snapshot
    /// `CssSelector`). Opaque here — it's handed back to the reader to be mapped to an `SDTPosition`.
    case reader(source: ReaderSourcePosition)
}

extension ReadAloudResumePosition {
    /// The synced `value` payload: `["pageIndex": Int, "rects": [[minX, minY, maxX, maxY]]]` for PDF, the reader's
    /// selector dictionary as it reported it for HTML/EPUB.
    var json: [String: Any] {
        switch self {
        case .pdf(let pageIndex, let rects):
            return ["pageIndex": pageIndex, "rects": rects.map({ [$0.minX, $0.minY, $0.maxX, $0.maxY] })]

        case .reader(let source):
            return source
        }
    }

    /// Parses a synced `value` payload. Nil when it is neither a PDF position nor a reader selector.
    init?(json: [String: Any]) {
        if let pageIndex = (json["pageIndex"] as? NSNumber)?.intValue {
            let rects = (json["rects"] as? [[Any]] ?? []).compactMap(ReadAloudResumePosition.rect(from:))
            self = .pdf(pageIndex: pageIndex, rects: rects)
            return
        }
        // Reader positions are WADM selectors, which always carry their selector type.
        guard json["type"] is String else { return nil }
        self = .reader(source: json)
    }

    /// `[minX, minY, maxX, maxY]`, as the backend sends it — numbers, or strings for non-integer values.
    private static func rect(from values: [Any]) -> CGRect? {
        guard values.count == 4 else { return nil }
        let doubles = values.compactMap({ value -> Double? in
            if let number = value as? NSNumber {
                return number.doubleValue
            }
            return (value as? String).flatMap(Double.init)
        })
        guard doubles.count == 4 else { return nil }
        return CGRect(x: doubles[0], y: doubles[1], width: doubles[2] - doubles[0], height: doubles[3] - doubles[1])
    }
}
