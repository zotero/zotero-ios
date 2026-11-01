//
//  SDTReadAloudSegmentsSpec.swift
//  ZoteroTests
//
//  Created by Miltiadis Vasilakis on 21.10.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

@testable import Zotero

import Nimble
import Quick

final class SDTReadAloudSegmentsSpec: QuickSpec {
    override class func spec() {
        describe("SDTReadAloudSegments") {
            it("joins the parts of a paragraph and drops a hard hyphen continued in lowercase") {
                let structure = document([
                    paragraph([["text": "A hyphen-"]], nextPart: [1]),
                    paragraph([["text": "ated word."]], previousPart: [0])
                ])

                let segments = SDTReadAloudSegments.segments(from: structure)

                expect(segments.map(\.text)).to(equal(["A hyphenated word."]))
                expect(segments.first?.start).to(equal([0, 0, 0]))
                expect(segments.first?.end).to(equal([1, 0, 10]))
                expect(segments.first?.isParagraphStart).to(beTrue())
            }

            it("separates words of adjacent parts with a space") {
                let structure = document([
                    paragraph([["text": "First"]], nextPart: [1]),
                    paragraph([["text": "second."]], previousPart: [0])
                ])

                expect(SDTReadAloudSegments.segments(from: structure).map(\.text)).to(equal(["First second."]))
            }

            it("leaves out a bracket group that is mostly linked text") {
                let structure = document([
                    paragraph([["text": "Claim "], ["text": "[12]", "refs": [["type": "reference"]]], ["text": " holds."]])
                ])

                let segments = SDTReadAloudSegments.segments(from: structure)

                expect(segments.map(\.text)).to(equal(["Claim holds."]))
                expect(segments.first?.start).to(equal([0, 0, 0]))
                expect(segments.first?.end).to(equal([0, 2, 7]))
            }

            it("keeps a parenthesized aside without links") {
                let structure = document([paragraph([["text": "Text (see above) here."]])])

                expect(SDTReadAloudSegments.segments(from: structure).map(\.text)).to(equal(["Text (see above) here."]))
            }

            it("leaves out a linked superscript marker") {
                let structure = document([
                    paragraph([["text": "Fact."], ["text": "3", "refs": [["type": "note"]], "style": ["sup": true]], ["text": " Next fact."]])
                ])

                let segments = SDTReadAloudSegments.segments(from: structure)

                expect(segments.map(\.text)).to(equal(["Fact.", "Next fact."]))
                expect(segments.map(\.isParagraphStart)).to(equal([true, false]))
            }

            it("skips blocks with an excluded top-level flowClass") {
                let structure = document([
                    ["type": "paragraph", "flowClass": "excluded", "content": [["text": "12"]]],
                    paragraph([["text": "Body."]])
                ])

                let segments = SDTReadAloudSegments.segments(from: structure)

                expect(segments.map(\.text)).to(equal(["Body."]))
                expect(segments.first?.start).to(equal([1, 0, 0]))
                expect(segments.first?.end).to(equal([1, 0, 5]))
            }

            it("anchors positions to nodes with visible text") {
                let structure = document([paragraph([["text": "   "], ["text": "Word."]])])

                let segments = SDTReadAloudSegments.segments(from: structure)

                expect(segments.map(\.text)).to(equal(["Word."]))
                expect(segments.first?.start).to(equal([0, 1, 0]))
                expect(segments.first?.end).to(equal([0, 1, 5]))
            }

            it("reads every leaf block as its own paragraph") {
                let structure = document([
                    ["type": "list", "content": [
                        ["type": "listitem", "content": [["text": "First item"]]],
                        ["type": "listitem", "content": [["text": "Second item"]]]
                    ]]
                ])

                let segments = SDTReadAloudSegments.segments(from: structure)

                expect(segments.map(\.text)).to(equal(["First item", "Second item"]))
                expect(segments.map(\.isParagraphStart)).to(equal([true, true]))
                expect(segments.map(\.start)).to(equal([[0, 0, 0, 0], [0, 1, 0, 0]]))
            }

            for fixture in ["1_epub", "1_advanced_epub", "2_epub", "2_advanced_epub", "3_epub", "1_html"] {
                it("builds well-formed segments for \(fixture)") {
                    let structure = loadStructure(named: "\(fixture)_structured_text")

                    let segments = SDTReadAloudSegments.segments(from: structure)

                    expect(segments).toNot(beEmpty())
                    expect(segments.first?.isParagraphStart).to(beTrue())
                    for segment in segments {
                        // Text as sent to the TTS server: whitespace collapsed and trimmed.
                        expect(segment.text).toNot(beEmpty())
                        expect(segment.text).to(equal(segment.text.trimmingCharacters(in: .whitespacesAndNewlines)))
                        expect(segment.text.contains("  ")).to(beFalse())
                        // Positions point into text nodes, in order.
                        expect(isTextPoint(segment.start, in: structure)).to(beTrue())
                        expect(isTextPoint(segment.end, in: structure)).to(beTrue())
                        expect(SDTContent.compareRefs(segment.start, segment.end)).to(beLessThanOrEqualTo(0))
                    }
                }
            }
        }

        func isTextPoint(_ point: [Int], in structure: [String: Any]) -> Bool {
            guard let offset = point.last, let text = SDTContent.text(of: SDTContent.node(at: Array(point.dropLast()), in: structure)) else { return false }
            return offset >= 0 && offset <= text.count
        }

        func document(_ content: [[String: Any]]) -> [String: Any] {
            return ["content": content]
        }

        func paragraph(_ nodes: [[String: Any]], previousPart: [Int]? = nil, nextPart: [Int]? = nil) -> [String: Any] {
            var block: [String: Any] = ["type": "paragraph", "content": nodes]
            block["previousPart"] = previousPart
            block["nextPart"] = nextPart
            return block
        }

        func loadStructure(named name: String) -> [String: Any] {
            let url = Bundle(for: SDTReadAloudSegmentsSpec.self).url(forResource: name, withExtension: "json")!
            let data = try! Data(contentsOf: url)
            return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        }
    }
}
