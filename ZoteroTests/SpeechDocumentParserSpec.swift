//
//  SpeechDocumentParserSpec.swift
//  ZoteroTests
//
//  Created by Michal Rentka on 2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

@testable import Zotero

import Nimble
import Quick

final class SpeechDocumentParserSpec: QuickSpec {
    override class func spec() {
        describe("SpeechDocumentParser") {
            describe("parse") {
                it("reads only paragraph and list blocks, skipping headings and other types") {
                    let materialized = document(blocks: [
                        paragraphBlock(page: 0, runs: [makeRun("First sentence. Second.", page: 0)]),
                        block(type: "heading", page: 0, runs: [makeRun("A Heading", page: 0)]),
                        block(type: "image", page: 0, runs: [makeRun("caption", page: 0)]),
                        paragraphBlock(page: 0, runs: [makeRun("Third.", page: 0)])
                    ])

                    let pages = SpeechDocumentParser.parse(materialized: materialized)

                    expect(pages.count).to(equal(1))
                    let page = pages[0]
                    expect(page).notTo(beNil())
                    expect(page?.paragraphRanges.count).to(equal(2))
                    expect(substring(page?.text ?? "", page!.paragraphRanges[0])).to(equal("First sentence. Second."))
                    expect(substring(page?.text ?? "", page!.paragraphRanges[1])).to(equal("Third."))
                    expect(page?.text.contains("A Heading")).to(beFalse())
                    expect(page?.text.contains("caption")).to(beFalse())
                }

                it("reads list blocks") {
                    let materialized = document(blocks: [
                        block(type: "list", page: 0, runs: [
                            ["content": [makeRun("Item one. ", page: 0)]],
                            ["content": [makeRun("Item two.", page: 0)]]
                        ])
                    ])

                    let pages = SpeechDocumentParser.parse(materialized: materialized)

                    expect(pages[0]?.paragraphRanges.count).to(equal(1))
                    expect(pages[0]?.text.contains("Item one.")).to(beTrue())
                    expect(pages[0]?.text.contains("Item two.")).to(beTrue())
                }

                it("skips blocks with excluded flowClass") {
                    let materialized = document(blocks: [
                        paragraphBlock(page: 0, flowClass: "excluded", runs: [makeRun("1", page: 0)]),
                        paragraphBlock(page: 0, runs: [makeRun("Real content.", page: 0)])
                    ])

                    let pages = SpeechDocumentParser.parse(materialized: materialized)

                    expect(pages[0]?.paragraphRanges.count).to(equal(1))
                    expect(substring(pages[0]?.text ?? "", pages[0]!.paragraphRanges[0])).to(equal("Real content."))
                }

                it("joins paragraphs on the same page with a blank line") {
                    let materialized = document(blocks: [
                        paragraphBlock(page: 0, runs: [makeRun("Alpha.", page: 0)]),
                        paragraphBlock(page: 0, runs: [makeRun("Beta.", page: 0)])
                    ])

                    let pages = SpeechDocumentParser.parse(materialized: materialized)

                    expect(pages[0]?.text).to(equal("Alpha.\n\nBeta."))
                    expect(pages[0]?.paragraphRanges.count).to(equal(2))
                }

                it("assigns runs to their page from the run textMap") {
                    let materialized = document(blocks: [
                        paragraphBlock(page: 3, runs: [makeRun("On page three.", page: 3)])
                    ])

                    let pages = SpeechDocumentParser.parse(materialized: materialized)

                    expect(Array(pages.keys)).to(equal([3]))
                    expect(pages[3]?.text).to(equal("On page three."))
                }

                it("splits a paragraph that spans two pages into per-page segments") {
                    let materialized = document(blocks: [
                        paragraphBlock(page: 0, runs: [
                            makeRun("Starts on page zero. ", page: 0),
                            makeRun("Continues on page one.", page: 1)
                        ])
                    ])

                    let pages = SpeechDocumentParser.parse(materialized: materialized)

                    expect(Set(pages.keys)).to(equal([0, 1]))
                    expect(pages[0]?.text).to(equal("Starts on page zero."))
                    expect(pages[0]?.paragraphRanges.count).to(equal(1))
                    expect(pages[1]?.text).to(equal("Continues on page one."))
                    expect(pages[1]?.paragraphRanges.count).to(equal(1))
                }

                it("assigns a run without a textMap to the surrounding page") {
                    let materialized = document(blocks: [
                        paragraphBlock(page: 2, runs: [
                            makeRun("Alpha", page: 2),
                            runWithoutTextMap(" "),
                            makeRun("Beta", page: 2)
                        ])
                    ])

                    let pages = SpeechDocumentParser.parse(materialized: materialized)

                    expect(Array(pages.keys)).to(equal([2]))
                    expect(pages[2]?.text).to(equal("Alpha Beta"))
                }

                it("returns nothing for empty or missing content") {
                    expect(SpeechDocumentParser.parse(materialized: ["content": []]).isEmpty).to(beTrue())
                    expect(SpeechDocumentParser.parse(materialized: [:]).isEmpty).to(beTrue())
                }
            }

            describe("language") {
                it("reads the lowercase language key (EPUB)") {
                    let materialized: [String: Any] = ["metadata": ["source": ["properties": ["language": "en-GB"]]]]
                    expect(SpeechDocumentParser.language(from: materialized)).to(equal("en-GB"))
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

            // Two paragraphs: "One. Two." at 0..<9, "Three. Four." at 11..<23 (separated by a blank line).
            let text = "One. Two.\n\nThree. Four."
            let ranges = [NSRange(location: 0, length: 9), NSRange(location: 11, length: 12)]

            describe("paragraphSegment") {
                it("returns from the index to the end of the containing paragraph") {
                    expect(SpeechDocumentParser.paragraphSegment(startingAt: 0, in: ranges)).to(equal(NSRange(location: 0, length: 9)))
                    expect(SpeechDocumentParser.paragraphSegment(startingAt: 5, in: ranges)).to(equal(NSRange(location: 5, length: 4)))
                }

                it("returns the next whole paragraph when the index is in the gap between paragraphs") {
                    expect(SpeechDocumentParser.paragraphSegment(startingAt: 9, in: ranges)).to(equal(NSRange(location: 11, length: 12)))
                }

                it("returns nil past the last paragraph") {
                    expect(SpeechDocumentParser.paragraphSegment(startingAt: 23, in: ranges)).to(beNil())
                    expect(SpeechDocumentParser.paragraphSegment(startingAt: 100, in: ranges)).to(beNil())
                }
            }

            describe("sentenceSegment") {
                it("returns the sentence starting at the index, bounded to its paragraph") {
                    expect(trimmed(text, SpeechDocumentParser.sentenceSegment(startingAt: 0, in: text, paragraphRanges: ranges))).to(equal("One."))
                    expect(trimmed(text, SpeechDocumentParser.sentenceSegment(startingAt: 5, in: text, paragraphRanges: ranges))).to(equal("Two."))
                }

                it("crosses into the next paragraph when the index is in the gap") {
                    expect(trimmed(text, SpeechDocumentParser.sentenceSegment(startingAt: 9, in: text, paragraphRanges: ranges))).to(equal("Three."))
                }

                it("never lets a sentence span a paragraph boundary") {
                    // No terminal punctuation after "beta", so a naive tokenizer could merge the two paragraphs.
                    let mergeText = "Alpha beta\n\nGamma delta."
                    let mergeRanges = [NSRange(location: 0, length: 10), NSRange(location: 12, length: 12)]
                    expect(trimmed(mergeText, SpeechDocumentParser.sentenceSegment(startingAt: 0, in: mergeText, paragraphRanges: mergeRanges))).to(equal("Alpha beta"))
                }

                it("returns nil past the last paragraph") {
                    expect(SpeechDocumentParser.sentenceSegment(startingAt: 100, in: text, paragraphRanges: ranges)).to(beNil())
                }
            }

            describe("nextSentenceStart") {
                it("advances to the next sentence within the paragraph") {
                    let start = SpeechDocumentParser.nextSentenceStart(after: 4, in: text, paragraphRanges: ranges)
                    expect(start).notTo(beNil())
                    expect(trimmed(text, SpeechDocumentParser.sentenceSegment(startingAt: start!, in: text, paragraphRanges: ranges))).to(equal("Two."))
                }

                it("advances past the sentence containing a mid-sentence index") {
                    // Emulates local-voice playback, where the position is word-level (mid-sentence).
                    let start = SpeechDocumentParser.nextSentenceStart(after: 2, in: text, paragraphRanges: ranges)
                    expect(start).notTo(beNil())
                    expect(trimmed(text, SpeechDocumentParser.sentenceSegment(startingAt: start!, in: text, paragraphRanges: ranges))).to(equal("Two."))
                }

                it("rolls into the first sentence of the next paragraph") {
                    let start = SpeechDocumentParser.nextSentenceStart(after: 9, in: text, paragraphRanges: ranges)
                    expect(start).notTo(beNil())
                    expect(trimmed(text, SpeechDocumentParser.sentenceSegment(startingAt: start!, in: text, paragraphRanges: ranges))).to(equal("Three."))
                }

                it("returns nil past the last sentence") {
                    expect(SpeechDocumentParser.nextSentenceStart(after: 23, in: text, paragraphRanges: ranges)).to(beNil())
                }
            }

            describe("previousSentenceStart") {
                it("returns the previous sentence within the paragraph") {
                    let start = SpeechDocumentParser.previousSentenceStart(before: 5, in: text, paragraphRanges: ranges)
                    expect(start).notTo(beNil())
                    expect(trimmed(text, SpeechDocumentParser.sentenceSegment(startingAt: start!, in: text, paragraphRanges: ranges))).to(equal("One."))
                }

                it("rolls back into the previous paragraph's last sentence") {
                    let start = SpeechDocumentParser.previousSentenceStart(before: 11, in: text, paragraphRanges: ranges)
                    expect(start).notTo(beNil())
                    expect(trimmed(text, SpeechDocumentParser.sentenceSegment(startingAt: start!, in: text, paragraphRanges: ranges))).to(equal("Two."))
                }

                it("returns nil at the first sentence of the first paragraph") {
                    expect(SpeechDocumentParser.previousSentenceStart(before: 0, in: text, paragraphRanges: ranges)).to(beNil())
                    expect(SpeechDocumentParser.previousSentenceStart(before: 2, in: text, paragraphRanges: ranges)).to(beNil())
                }
            }

            describe("lastSentenceStart") {
                it("returns the last sentence of the last paragraph") {
                    let start = SpeechDocumentParser.lastSentenceStart(in: text, paragraphRanges: ranges)
                    expect(start).notTo(beNil())
                    expect(trimmed(text, SpeechDocumentParser.sentenceSegment(startingAt: start!, in: text, paragraphRanges: ranges))).to(equal("Four."))
                }

                it("returns nil when there are no paragraphs") {
                    expect(SpeechDocumentParser.lastSentenceStart(in: text, paragraphRanges: [])).to(beNil())
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

/// Builds a run whose page is encoded in the textMap (page is the second element, matching the SDT format).
private func makeRun(_ text: String, page: Int) -> [String: Any] {
    return ["text": text, "anchor": ["textMap": "[[0,\(page),0,0,0,0]]"]]
}

private func runWithoutTextMap(_ text: String) -> [String: Any] {
    return ["text": text]
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
