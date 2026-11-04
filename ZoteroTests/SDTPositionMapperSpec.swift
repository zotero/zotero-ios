//
//  SDTPositionMapperSpec.swift
//  ZoteroTests
//
//  Created by Michal Rentka on 04.11.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

@testable import Zotero

import Nimble
import Quick

/// Expected values follow the reader's `EPUBPositionMapper` and `SnapshotPositionMapper` (`reader/src/common/sdt`), update them
/// together with `SDTPositionMapper`.
final class SDTPositionMapperSpec: QuickSpec {
    override class func spec() {
        describe("SDTPositionMapper") {
            it("isn't created for PDF") {
                expect(SDTPositionMapper(structure: ["metadata": ["processor": ["type": "pdf"]], "content": []])).to(beNil())
            }

            it("passes SDT positions through") {
                let mapper = SDTPositionMapper(structure: epub([]))

                let position = mapper?.sdtPosition(for: ["start": [0, 0, 1], "end": [0, 0, 2]])

                expect(position?.start).to(equal([0, 0, 1]))
                expect(position?.end).to(equal([0, 0, 2]))
            }

            context("EPUB") {
                let structure = epub([
                    paragraph(selectorMap: "/6/4!/4/2", [["text": "Hello world.", "anchor": ["selectorMap": "/1"]]]),
                    paragraph(selectorMap: "/6/4!/4/4", [["text": "Next one.", "anchor": ["selectorMap": "/1"]]])
                ])

                it("maps a range within a text node to a CFI range") {
                    let source = SDTPositionMapper(structure: structure)?.sourcePosition(for: SDTPosition(start: [0, 0, 0], end: [0, 0, 5]))

                    expect(source?["type"] as? String).to(equal("FragmentSelector"))
                    expect(source?["value"] as? String).to(equal("epubcfi(/6/4!/4/2/1,:0,:5)"))
                }

                it("maps a single character to a CFI point") {
                    let source = SDTPositionMapper(structure: structure)?.sourcePosition(for: SDTPosition(start: [0, 0, 6], end: [0, 0, 7]))

                    expect(source?["value"] as? String).to(equal("epubcfi(/6/4!/4/2/1:6)"))
                }

                it("maps a range across blocks to a CFI range with a common path") {
                    let source = SDTPositionMapper(structure: structure)?.sourcePosition(for: SDTPosition(start: [0, 0, 6], end: [1, 0, 4]))

                    expect(source?["value"] as? String).to(equal("epubcfi(/6/4!/4,/2/1:6,/4/1:4)"))
                }

                it("maps a CFI range back to an SDT position") {
                    let position = SDTPositionMapper(structure: structure)?.sdtPosition(for: cfi("epubcfi(/6/4!/4,/2/1:6,/4/1:4)"))

                    expect(position?.start).to(equal([0, 0, 6]))
                    expect(position?.end).to(equal([1, 0, 4]))
                }

                it("ignores CFI assertions") {
                    let position = SDTPositionMapper(structure: structure)?.sdtPosition(for: cfi("epubcfi(/6/4[chap01]!/4[body01]/2/1:3)"))

                    expect(position?.start).to(equal([0, 0, 3]))
                    expect(position?.end).to(equal([0, 0, 3]))
                }

                it("falls back to block boundaries for paths without a text node") {
                    let position = SDTPositionMapper(structure: structure)?.sdtPosition(for: cfi("epubcfi(/6/4!/4/4/3:0)"))

                    expect(position?.start).to(equal([1]))
                    expect(position?.end).to(equal([2]))
                }

                it("translates offsets between NFC and the original text") {
                    // "café" with a decomposed "é" is one character longer in the original text.
                    let structure = epub([paragraph(selectorMap: "/4/2", [["text": "café", "anchor": ["selectorMap": "/1", "deltaMap": "4 -1"]]])])
                    let mapper = SDTPositionMapper(structure: structure)

                    expect(mapper?.sourcePosition(for: SDTPosition(start: [0, 0, 0], end: [0, 0, 4]))?["value"] as? String).to(equal("epubcfi(/4/2/1,:0,:5)"))
                    expect(mapper?.sdtPosition(for: cfi("epubcfi(/4/2/1,:0,:5)"))?.end).to(equal([0, 0, 4]))
                }
            }

            context("snapshot") {
                let structure: SDTContent.Node = [
                    "metadata": ["processor": ["type": "snapshot"]],
                    "catalog": [
                        "domMap": [
                            ["tag": "p", "index": 0, "flags": 1, "textStart": 0, "textLength": 12],
                            ["tag": "p", "index": 1, "flags": 6, "textStart": 12, "textLength": 10]
                        ]
                    ],
                    "content": [
                        ["type": "paragraph", "content": [["text": "Hello world.", "anchor": ["stream": 0]]]],
                        ["type": "paragraph", "content": [["text": "Second one", "anchor": ["stream": 12]]]]
                    ]
                ]

                it("maps a whole element to a CSS selector") {
                    let source = SDTPositionMapper(structure: structure)?.sourcePosition(for: SDTPosition(start: [0, 0, 0], end: [0, 0, 12]))

                    expect(source?["type"] as? String).to(equal("CssSelector"))
                    expect(source?["value"] as? String).to(equal("body > p:first-child"))
                    expect(source?["refinedBy"]).to(beNil())
                }

                it("refines a CSS selector by a text position") {
                    let source = SDTPositionMapper(structure: structure)?.sourcePosition(for: SDTPosition(start: [1, 0, 0], end: [1, 0, 6]))
                    let refinedBy = source?["refinedBy"] as? [String: Any]

                    expect(source?["value"] as? String).to(equal("body > p:last-child"))
                    expect(refinedBy?["type"] as? String).to(equal("TextPositionSelector"))
                    expect(refinedBy?["start"] as? Int).to(equal(0))
                    expect(refinedBy?["end"] as? Int).to(equal(6))
                }

                it("maps a range across elements to a body text position") {
                    let source = SDTPositionMapper(structure: structure)?.sourcePosition(for: SDTPosition(start: [0, 0, 6], end: [1, 0, 6]))

                    expect(source?["type"] as? String).to(equal("TextPositionSelector"))
                    expect(source?["start"] as? Int).to(equal(6))
                    expect(source?["end"] as? Int).to(equal(18))
                }

                it("maps a refined CSS selector back to an SDT position") {
                    let source: ReaderSourcePosition = [
                        "type": "CssSelector",
                        "value": "body > p:last-child",
                        "refinedBy": ["type": "TextPositionSelector", "start": 0, "end": 6]
                    ]

                    let position = SDTPositionMapper(structure: structure)?.sdtPosition(for: source)

                    expect(position?.start).to(equal([1, 0, 0]))
                    expect(position?.end).to(equal([1, 0, 6]))
                }

                it("maps a body text position back to an SDT position") {
                    let position = SDTPositionMapper(structure: structure)?.sdtPosition(for: ["type": "TextPositionSelector", "start": 6, "end": 18])

                    expect(position?.start).to(equal([0, 0, 6]))
                    expect(position?.end).to(equal([1, 0, 6]))
                }

                it("roots selectors at the nearest element with an id, escaped like CSS.escape") {
                    let structure: SDTContent.Node = [
                        "metadata": ["processor": ["type": "snapshot"]],
                        "catalog": ["domMap": [["tag": "section", "index": 0, "flags": 3, "id": "1a", "textStart": 0, "textLength": 5]]],
                        "content": [["type": "paragraph", "content": [["text": "Hello", "anchor": ["stream": 0]]]]]
                    ]
                    let mapper = SDTPositionMapper(structure: structure)

                    expect(mapper?.sourcePosition(for: SDTPosition(start: [0, 0, 0], end: [0, 0, 5]))?["value"] as? String).to(equal("#\\31 a"))
                    expect(mapper?.sdtPosition(for: ["type": "CssSelector", "value": "#\\31 a"])?.end).to(equal([0, 0, 5]))
                }
            }
        }

        func epub(_ content: [SDTContent.Node]) -> SDTContent.Node {
            return ["metadata": ["processor": ["type": "epub"]], "content": content]
        }

        func paragraph(selectorMap: String, _ content: [SDTContent.Node]) -> SDTContent.Node {
            return ["type": "paragraph", "anchor": ["selectorMap": selectorMap], "content": content]
        }

        func cfi(_ value: String) -> ReaderSourcePosition {
            return ["type": "FragmentSelector", "value": value]
        }
    }
}
