//
//  SpeechDocumentParserSpec.swift
//  ZoteroTests
//
//  Created by Michal Rentka on 2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import CoreGraphics
import Foundation

@testable import Zotero

import Nimble
import Quick

final class SpeechDocumentParserSpec: QuickSpec {
    override class func spec() {
        describe("SpeechDocumentParser") {
            describe("parse") {
                it("reads every block type but skips blocks with an excluded flowClass") {
                    let materialized = document(blocks: [
                        paragraphBlock(page: 0, runs: [makeRun("First sentence. Second.", page: 0)]),
                        // Non-paragraph block types are read too (block type is not filtered).
                        block(type: "heading", page: 0, runs: [makeRun("A Heading", page: 0)]),
                        block(type: "image", page: 0, runs: [makeRun("caption", page: 0)]),
                        // Excluded flowClasses (page numbers, running headers/footers, …) are the only blocks dropped.
                        paragraphBlock(page: 0, flowClass: "excluded", runs: [makeRun("42", page: 0)]),
                        paragraphBlock(page: 0, flowClass: "auxiliary", runs: [makeRun("Running header", page: 0)]),
                        paragraphBlock(page: 0, runs: [makeRun("Third.", page: 0)])
                    ])

                    let paragraphs = SpeechDocumentParser.parse(materialized: materialized).paragraphs

                    expect(paragraphs.map(\.text)).to(equal(["First sentence. Second.", "A Heading", "caption", "Third."]))
                    expect(paragraphs.allSatisfy { $0.page == 0 }).to(beTrue())
                }

                it("reads list blocks") {
                    let materialized = document(blocks: [
                        block(type: "list", page: 0, runs: [
                            ["content": [makeRun("Item one. ", page: 0)]],
                            ["content": [makeRun("Item two.", page: 0)]]
                        ])
                    ])

                    let paragraphs = SpeechDocumentParser.parse(materialized: materialized).paragraphs

                    expect(paragraphs.count).to(equal(1))
                    expect(paragraphs.first?.text.contains("Item one.")).to(beTrue())
                    expect(paragraphs.first?.text.contains("Item two.")).to(beTrue())
                }

                it("skips blocks with excluded flowClass") {
                    let materialized = document(blocks: [
                        paragraphBlock(page: 0, flowClass: "excluded", runs: [makeRun("1", page: 0)]),
                        paragraphBlock(page: 0, runs: [makeRun("Real content.", page: 0)])
                    ])

                    let paragraphs = SpeechDocumentParser.parse(materialized: materialized).paragraphs

                    expect(paragraphs.map(\.text)).to(equal(["Real content."]))
                }

                it("assigns page offsets so paragraphs on a page are separated by a blank line") {
                    let materialized = document(blocks: [
                        paragraphBlock(page: 0, runs: [makeRun("Alpha.", page: 0)]),
                        paragraphBlock(page: 0, runs: [makeRun("Beta.", page: 0)])
                    ])

                    let paragraphs = SpeechDocumentParser.parse(materialized: materialized).paragraphs

                    expect(paragraphs.count).to(equal(2))
                    expect(paragraphs[0].pageOffset).to(equal(0))
                    // "Alpha." (6 chars) + "\n\n" (2 chars) = 8
                    expect(paragraphs[1].pageOffset).to(equal(8))
                }

                it("assigns paragraphs to their page from the run textMap") {
                    let materialized = document(blocks: [
                        paragraphBlock(page: 3, runs: [makeRun("On page three.", page: 3)])
                    ])

                    let paragraphs = SpeechDocumentParser.parse(materialized: materialized).paragraphs

                    expect(paragraphs.count).to(equal(1))
                    expect(paragraphs.first?.page).to(equal(3))
                    expect(paragraphs.first?.pageOffset).to(equal(0))
                }

                it("splits a paragraph that spans two pages into one paragraph per page") {
                    let materialized = document(blocks: [
                        paragraphBlock(page: 0, runs: [
                            makeRun("Starts on page zero. ", page: 0),
                            makeRun("Continues on page one.", page: 1)
                        ])
                    ])

                    let paragraphs = SpeechDocumentParser.parse(materialized: materialized).paragraphs

                    expect(paragraphs.count).to(equal(2))
                    expect(paragraphs[0].page).to(equal(0))
                    expect(paragraphs[0].text).to(equal("Starts on page zero."))
                    expect(paragraphs[0].pageOffset).to(equal(0))
                    expect(paragraphs[1].page).to(equal(1))
                    expect(paragraphs[1].text).to(equal("Continues on page one."))
                    expect(paragraphs[1].pageOffset).to(equal(0))
                }

                it("assigns a run without a textMap to the surrounding page") {
                    let materialized = document(blocks: [
                        paragraphBlock(page: 2, runs: [
                            makeRun("Alpha", page: 2),
                            runWithoutTextMap(" "),
                            makeRun("Beta", page: 2)
                        ])
                    ])

                    let paragraphs = SpeechDocumentParser.parse(materialized: materialized).paragraphs

                    expect(paragraphs.count).to(equal(1))
                    expect(paragraphs.first?.page).to(equal(2))
                    expect(paragraphs.first?.text).to(equal("Alpha Beta"))
                }

                it("returns no paragraphs for empty or missing content") {
                    expect(SpeechDocumentParser.parse(materialized: ["content": []]).paragraphs.isEmpty).to(beTrue())
                    expect(SpeechDocumentParser.parse(materialized: [:]).paragraphs.isEmpty).to(beTrue())
                }
            }

            describe("citation elision") {
                it("removes a bracketed numeric citation that links to a reference") {
                    let materialized = document(blocks: [
                        paragraphBlock(page: 0, runs: [
                            makeRun("This matters ", page: 0),
                            makeRun("[2]", page: 0, hasRefs: true),
                            makeRun(".", page: 0)
                        ])
                    ])

                    let paragraphs = SpeechDocumentParser.parse(materialized: materialized).paragraphs

                    expect(paragraphs.map(\.text)).to(equal(["This matters ."]))
                }

                it("removes a parenthetical author-year citation that links to a reference") {
                    let materialized = document(blocks: [
                        paragraphBlock(page: 0, runs: [
                            makeRun("As shown ", page: 0),
                            makeRun("(Smith 2026)", page: 0, hasRefs: true),
                            makeRun(" it works.", page: 0)
                        ])
                    ])

                    let paragraphs = SpeechDocumentParser.parse(materialized: materialized).paragraphs

                    // The elided range is removed verbatim, leaving the surrounding spaces (no whitespace collapsing, matching desktop).
                    expect(paragraphs.map(\.text)).to(equal(["As shown  it works."]))
                }

                it("keeps a bracketed aside that is not a reference link") {
                    let materialized = document(blocks: [
                        paragraphBlock(page: 0, runs: [makeRun("This is verbatim [sic] text.", page: 0)])
                    ])

                    let paragraphs = SpeechDocumentParser.parse(materialized: materialized).paragraphs

                    expect(paragraphs.map(\.text)).to(equal(["This is verbatim [sic] text."]))
                }

                it("keeps a parenthetical group whose linked coverage is below the threshold") {
                    let materialized = document(blocks: [
                        paragraphBlock(page: 0, runs: [
                            makeRun("Note ", page: 0),
                            makeRun("(see the discussion around ", page: 0),
                            makeRun("2", page: 0, hasRefs: true),
                            makeRun(" for context)", page: 0)
                        ])
                    ])

                    let paragraphs = SpeechDocumentParser.parse(materialized: materialized).paragraphs

                    expect(paragraphs.map(\.text)).to(equal(["Note (see the discussion around 2 for context)"]))
                }

                it("removes a superscript reference marker") {
                    let materialized = document(blocks: [
                        paragraphBlock(page: 0, runs: [
                            makeRun("Some claim", page: 0),
                            makeRun("3", page: 0, hasRefs: true, sup: true),
                            makeRun(" continues.", page: 0)
                        ])
                    ])

                    let paragraphs = SpeechDocumentParser.parse(materialized: materialized).paragraphs

                    expect(paragraphs.map(\.text)).to(equal(["Some claim continues."]))
                }

                it("keeps a superscript marker that does not link to a reference") {
                    let materialized = document(blocks: [
                        paragraphBlock(page: 0, runs: [
                            makeRun("E = mc", page: 0),
                            makeRun("2", page: 0, sup: true)
                        ])
                    ])

                    let paragraphs = SpeechDocumentParser.parse(materialized: materialized).paragraphs

                    expect(paragraphs.map(\.text)).to(equal(["E = mc2"]))
                }

                it("keeps an inline reference link that is neither bracketed nor superscript") {
                    let materialized = document(blocks: [
                        paragraphBlock(page: 0, runs: [
                            makeRun("See ", page: 0),
                            makeRun("Smith and Jones", page: 0, hasRefs: true),
                            makeRun(" for more.", page: 0)
                        ])
                    ])

                    let paragraphs = SpeechDocumentParser.parse(materialized: materialized).paragraphs

                    expect(paragraphs.map(\.text)).to(equal(["See Smith and Jones for more."]))
                }
            }

            describe("charRects") {
                it("aligns a per-character rect with each character of the readable text") {
                    let materialized = document(blocks: [
                        paragraphBlock(page: 0, runs: [glyphRun("Hello", page: 0, x: 0, charWidth: 5, top: 0, height: 10)])
                    ])

                    guard let paragraph = SpeechDocumentParser.parse(materialized: materialized).paragraphs.first else {
                        fail("expected a paragraph"); return
                    }
                    expect(paragraph.text).to(equal("Hello"))
                    expect(paragraph.charRects.count).to(equal(5))
                    expect(paragraph.charRects[0]).to(equal(rect(0, 0, 5, 10)))
                    expect(paragraph.charRects[4]).to(equal(rect(20, 0, 5, 10)))
                }

                it("assigns nil to whitespace characters") {
                    let materialized = document(blocks: [
                        paragraphBlock(page: 0, runs: [glyphRun("a b", page: 0, x: 0, charWidth: 5)])
                    ])

                    guard let paragraph = SpeechDocumentParser.parse(materialized: materialized).paragraphs.first else {
                        fail("expected a paragraph"); return
                    }
                    expect(paragraph.text).to(equal("a b"))
                    expect(paragraph.charRects[0]).to(equal(rect(0, 0, 5, 10)))
                    expect(paragraph.charRects[1]).to(beNil())
                    expect(paragraph.charRects[2]).to(equal(rect(5, 0, 5, 10)))
                }

                it("drops a citation's geometry along with its text") {
                    let materialized = document(blocks: [
                        paragraphBlock(page: 0, runs: [
                            glyphRun("Ref ", page: 0, x: 0, charWidth: 5),
                            glyphRun("[2]", page: 0, x: 100, charWidth: 5, hasRefs: true),
                            glyphRun(" end", page: 0, x: 200, charWidth: 5)
                        ])
                    ])

                    guard let paragraph = SpeechDocumentParser.parse(materialized: materialized).paragraphs.first else {
                        fail("expected a paragraph"); return
                    }
                    // "[2]" is elided; the surrounding spaces remain, and no rect at x=100 survives.
                    expect(paragraph.text).to(equal("Ref  end"))
                    expect(paragraph.charRects.count).to(equal(8))
                    expect(paragraph.charRects.compactMap { $0?.minX }).to(equal([0, 5, 10, 200, 205, 210]))
                }
            }

            describe("pdfLineRects") {
                // "abcd" laid out as four 5-wide glyphs on one line (y 0–10).
                let oneLine = SpeechDocumentParser.Segment(
                    text: "abcd",
                    pageOffset: 0,
                    charRects: [rect(0, 0, 5, 10), rect(5, 0, 5, 10), rect(10, 0, 5, 10), rect(15, 0, 5, 10)]
                )

                it("merges rects on the same line into one") {
                    let rects = SpeechDocumentParser.pdfLineRects(forRange: NSRange(location: 0, length: 4), in: [oneLine])
                    expect(rects).to(equal([rect(0, 0, 20, 10)]))
                }

                it("covers only the requested sub-range") {
                    let rects = SpeechDocumentParser.pdfLineRects(forRange: NSRange(location: 1, length: 2), in: [oneLine])
                    expect(rects).to(equal([rect(5, 0, 10, 10)]))
                }

                it("splits rects that fall on different lines") {
                    let twoLines = SpeechDocumentParser.Segment(
                        text: "abcd",
                        pageOffset: 0,
                        charRects: [rect(0, 0, 5, 10), rect(5, 0, 5, 10), rect(0, 20, 5, 10), rect(5, 20, 5, 10)]
                    )
                    let rects = SpeechDocumentParser.pdfLineRects(forRange: NSRange(location: 0, length: 4), in: [twoLines])
                    expect(rects).to(equal([rect(0, 0, 10, 10), rect(0, 20, 10, 10)]))
                }

                it("spans a range across two segments and skips the separator gap") {
                    let first = SpeechDocumentParser.Segment(text: "ab", pageOffset: 0, charRects: [rect(0, 0, 5, 10), rect(5, 0, 5, 10)])
                    // Second segment starts after "ab" + the two-character separator, at offset 4.
                    let second = SpeechDocumentParser.Segment(text: "cd", pageOffset: 4, charRects: [rect(0, 20, 5, 10), rect(5, 20, 5, 10)])
                    let rects = SpeechDocumentParser.pdfLineRects(forRange: NSRange(location: 0, length: 6), in: [first, second])
                    expect(rects).to(equal([rect(0, 0, 10, 10), rect(0, 20, 10, 10)]))
                }

                it("returns no rects for an empty range") {
                    expect(SpeechDocumentParser.pdfLineRects(forRange: NSRange(location: 0, length: 0), in: [oneLine])).to(beEmpty())
                }
            }

            describe("language") {
                it("reads the lowercase language key (EPUB)") {
                    let materialized: [String: Any] = ["metadata": ["source": ["properties": ["language": "en-GB"]]]]
                    expect(SpeechDocumentParser.parse(materialized: materialized).language).to(equal("en-GB"))
                }

                it("reads the capitalized Language key (PDF)") {
                    let materialized: [String: Any] = ["metadata": ["source": ["properties": ["Language": "de-DE"]]]]
                    expect(SpeechDocumentParser.language(from: materialized)).to(equal("de-DE"))
                }

                it("returns nil when the language is absent") {
                    let materialized: [String: Any] = ["metadata": ["source": ["properties": ["title": "Something"]]]]
                    expect(SpeechDocumentParser.language(from: materialized)).to(beNil())
                }

                it("returns nil when metadata is missing") {
                    expect(SpeechDocumentParser.language(from: ["content": []])).to(beNil())
                }

                it("returns nil for an empty or whitespace language") {
                    expect(SpeechDocumentParser.language(from: ["metadata": ["source": ["properties": ["language": ""]]]])).to(beNil())
                    expect(SpeechDocumentParser.language(from: ["metadata": ["source": ["properties": ["language": "   "]]]])).to(beNil())
                }
            }

            // Two segments (paragraphs) on a page: "One. Two." at page-text offset 0, "Three. Four." at offset 11.
            // The page text (segments joined by a blank line) is "One. Two.\n\nThree. Four.".
            let text = "One. Two.\n\nThree. Four."
            let segments = [
                SpeechDocumentParser.Segment(text: "One. Two.", pageOffset: 0),
                SpeechDocumentParser.Segment(text: "Three. Four.", pageOffset: 11)
            ]

            describe("paragraphRange") {
                it("returns from the index to the end of the containing segment") {
                    expect(SpeechDocumentParser.paragraphRange(startingAt: 0, in: segments)).to(equal(NSRange(location: 0, length: 9)))
                    expect(SpeechDocumentParser.paragraphRange(startingAt: 5, in: segments)).to(equal(NSRange(location: 5, length: 4)))
                }

                it("returns the next whole segment when the index is in the gap between segments") {
                    expect(SpeechDocumentParser.paragraphRange(startingAt: 9, in: segments)).to(equal(NSRange(location: 11, length: 12)))
                }

                it("returns nil past the last segment") {
                    expect(SpeechDocumentParser.paragraphRange(startingAt: 23, in: segments)).to(beNil())
                    expect(SpeechDocumentParser.paragraphRange(startingAt: 100, in: segments)).to(beNil())
                }
            }

            describe("sentenceRange") {
                it("returns the sentence starting at the index, within its segment") {
                    expect(trimmed(text, SpeechDocumentParser.sentenceRange(startingAt: 0, in: segments))).to(equal("One."))
                    expect(trimmed(text, SpeechDocumentParser.sentenceRange(startingAt: 5, in: segments))).to(equal("Two."))
                }

                it("crosses into the next segment when the index is in the gap") {
                    expect(trimmed(text, SpeechDocumentParser.sentenceRange(startingAt: 9, in: segments))).to(equal("Three."))
                }

                it("never lets a sentence span a paragraph boundary") {
                    // No terminal punctuation after "beta", so a naive tokenizer over the joined text could merge the paragraphs.
                    let mergeText = "Alpha beta\n\nGamma delta."
                    let mergeSegments = [
                        SpeechDocumentParser.Segment(text: "Alpha beta", pageOffset: 0),
                        SpeechDocumentParser.Segment(text: "Gamma delta.", pageOffset: 12)
                    ]
                    expect(trimmed(mergeText, SpeechDocumentParser.sentenceRange(startingAt: 0, in: mergeSegments))).to(equal("Alpha beta"))
                }

                it("returns nil past the last segment") {
                    expect(SpeechDocumentParser.sentenceRange(startingAt: 100, in: segments)).to(beNil())
                }
            }

            describe("nextSentenceStart") {
                it("advances to the next sentence within the segment") {
                    let start = SpeechDocumentParser.nextSentenceStart(after: 4, in: segments)
                    expect(start).notTo(beNil())
                    expect(trimmed(text, SpeechDocumentParser.sentenceRange(startingAt: start!, in: segments))).to(equal("Two."))
                }

                it("advances past the sentence containing a mid-sentence index") {
                    // Emulates local-voice playback, where the position is word-level (mid-sentence).
                    let start = SpeechDocumentParser.nextSentenceStart(after: 2, in: segments)
                    expect(start).notTo(beNil())
                    expect(trimmed(text, SpeechDocumentParser.sentenceRange(startingAt: start!, in: segments))).to(equal("Two."))
                }

                it("rolls into the first sentence of the next segment") {
                    let start = SpeechDocumentParser.nextSentenceStart(after: 9, in: segments)
                    expect(start).notTo(beNil())
                    expect(trimmed(text, SpeechDocumentParser.sentenceRange(startingAt: start!, in: segments))).to(equal("Three."))
                }

                it("returns nil past the last sentence") {
                    expect(SpeechDocumentParser.nextSentenceStart(after: 23, in: segments)).to(beNil())
                }
            }

            describe("previousSentenceStart") {
                it("returns the previous sentence within the segment") {
                    let start = SpeechDocumentParser.previousSentenceStart(before: 5, in: segments)
                    expect(start).notTo(beNil())
                    expect(trimmed(text, SpeechDocumentParser.sentenceRange(startingAt: start!, in: segments))).to(equal("One."))
                }

                it("rolls back into the previous segment's last sentence") {
                    let start = SpeechDocumentParser.previousSentenceStart(before: 11, in: segments)
                    expect(start).notTo(beNil())
                    expect(trimmed(text, SpeechDocumentParser.sentenceRange(startingAt: start!, in: segments))).to(equal("Two."))
                }

                it("returns nil at the first sentence of the first segment") {
                    expect(SpeechDocumentParser.previousSentenceStart(before: 0, in: segments)).to(beNil())
                    expect(SpeechDocumentParser.previousSentenceStart(before: 2, in: segments)).to(beNil())
                }
            }

            describe("lastSentenceStart") {
                it("returns the last sentence of the last segment") {
                    let start = SpeechDocumentParser.lastSentenceStart(in: segments)
                    expect(start).notTo(beNil())
                    expect(trimmed(text, SpeechDocumentParser.sentenceRange(startingAt: start!, in: segments))).to(equal("Four."))
                }

                it("returns nil when there are no segments") {
                    expect(SpeechDocumentParser.lastSentenceStart(in: [])).to(beNil())
                }
            }
        }
    }
}

// MARK: - Helpers

/// Extracts a substring using character offsets (matching the ranges the parser produces).
private func substring(_ text: String, _ range: NSRange) -> String {
    let start = text.index(text.startIndex, offsetBy: range.location)
    let end = text.index(start, offsetBy: range.length)
    return String(text[start..<end])
}

private func trimmed(_ text: String, _ range: NSRange?) -> String? {
    guard let range else { return nil }
    return substring(text, range).trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Builds a run whose page is encoded in the textMap (page is the second element, matching the SDT format). `hasRefs`
/// gives the run a non-empty `refs` array (it links to a reference), and `sup` marks it superscript — both drive citation elision.
private func makeRun(_ text: String, page: Int, hasRefs: Bool = false, sup: Bool = false) -> [String: Any] {
    var run: [String: Any] = ["text": text, "anchor": ["textMap": "[[0,\(page),0,0,0,0]]"]]
    if hasRefs {
        run["refs"] = [[0]]
    }
    if sup {
        run["style"] = ["sup": true]
    }
    return run
}

private func runWithoutTextMap(_ text: String) -> [String: Any] {
    return ["text": text]
}

/// Builds a run whose `textMap` encodes real per-character geometry: every non-whitespace character gets a rect of
/// width `charWidth` laid out left-to-right from `x`, on a line spanning `[top, top + height)`. Whitespace characters
/// get no rect (matching the structured document text's own layout). Lets tests assert `charRects` and `pdfLineRects`.
private func glyphRun(
    _ text: String,
    page: Int,
    x: Double = 0,
    charWidth: Double = 5,
    top: Double = 0,
    height: Double = 10,
    hasRefs: Bool = false,
    sup: Bool = false
) -> [String: Any] {
    let glyphCount = text.filter { $0 != " " && $0 != "\n" && $0 != "\t" }.count
    let widths = Array(repeating: charWidth, count: glyphCount)
    let maxX = x + charWidth * Double(glyphCount)
    let widthsJSON = widths.map { String(format: "%g", $0) }.joined(separator: ",")
    let prefix = "0,\(page),\(x),\(top),\(maxX),\(top + height)"
    let textMap = glyphCount > 0 ? "[[\(prefix),\(widthsJSON)]]" : "[[\(prefix)]]"

    var run: [String: Any] = ["text": text, "anchor": ["textMap": textMap]]
    if hasRefs {
        run["refs"] = [[0]]
    }
    if sup {
        run["style"] = ["sup": true]
    }
    return run
}

private func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> CGRect {
    return CGRect(x: x, y: y, width: width, height: height)
}

private func block(type: String, page: Int, flowClass: String? = nil, runs: [[String: Any]]) -> [String: Any] {
    var block: [String: Any] = [
        "type": type,
        "anchor": ["pageRects": [[page, 0, 0, 0, 0]]],
        "content": runs
    ]
    if let flowClass {
        block["flowClass"] = flowClass
    }
    return block
}

private func paragraphBlock(page: Int, flowClass: String? = nil, runs: [[String: Any]]) -> [String: Any] {
    return block(type: "paragraph", page: page, flowClass: flowClass, runs: runs)
}

private func document(blocks: [[String: Any]]) -> [String: Any] {
    return ["content": blocks]
}
