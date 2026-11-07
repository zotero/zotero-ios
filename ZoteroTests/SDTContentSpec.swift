//
//  SDTContentSpec.swift
//  ZoteroTests
//
//  Created by Miltiadis Vasilakis on 21.10.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

@testable import Zotero

import Nimble
import Quick

/// Checks the `SDTContent` port against `zotero/structured-document-text` through its full text extraction: the hand-written
/// cases and the fixtures of `test/fulltext.test.js`. The EPUB and snapshot fixture structures are the same as the
/// `*_structured_text.json` files used by `DocumentWorkerControllerSpec` (identical content and page ranges), so those are
/// reused, with the submodule's expected `*.fulltext.txt` outputs.
final class SDTContentSpec: QuickSpec {
    override class func spec() {
        describe("SDTContent") {
            describe("full text") {
                it("uses half-open page content ranges over top-level blocks") {
                    let structure = document(pages: [[[0], [2]], [[2], [3]]], content: [
                        paragraph("abcdef"),
                        ["type": "list", "content": [listItem("hello"), listItem("world")]],
                        paragraph("outside")
                    ])

                    expect(fulltext(structure, [0])).to(equal("abcdef\n\nhello\nworld"))
                    expect(fulltext(structure, [1])).to(equal("outside"))
                    expect(fulltext(structure, [1, 0])).to(equal("outside\n\nabcdef\n\nhello\nworld"))
                }

                it("emits continuation chains once when all parts are in the selected pages") {
                    let structure = document(pages: [[[0], [2]]], content: [
                        paragraph("abcdef", nextPart: [1]),
                        paragraph("ghij", previousPart: [0])
                    ])

                    expect(fulltext(structure, [0])).to(equal("abcdef ghij"))
                }

                it("keeps page-split slices of a block together in part chains") {
                    let structure = document(pages: [[[0], [0, 0, 11]], [[0, 0, 11], [2]]], content: [
                        paragraph("first-half second-half", nextPart: [1]),
                        paragraph("continuation.", previousPart: [0])
                    ])

                    expect(fulltext(structure, [0, 1])).to(equal("first-half second-half continuation."))
                    expect(fulltext(structure, [0])).to(equal("first-half"))
                    expect(fulltext(structure, [1])).to(equal("second-half continuation."))
                }

                it("drops hard hyphen at explicit part boundaries") {
                    let structure = document(pages: [[[0], [2]]], content: [
                        paragraph("hyphen-", nextPart: [1]),
                        paragraph("ated", previousPart: [0])
                    ])

                    expect(fulltext(structure, [0])).to(equal("hyphenated"))
                }

                it("keeps hard hyphen when the next part is not a lowercase continuation") {
                    let structure = document(pages: [[[0], [2]]], content: [
                        paragraph("Object-", nextPart: [1]),
                        paragraph("Shape", previousPart: [0])
                    ])

                    expect(fulltext(structure, [0])).to(equal("Object-Shape"))
                }

                it("treats a nested end boundary as before that child") {
                    let structure = document(pages: [[[0], [1, 0]], [[1, 0], [2]]], content: [
                        paragraph("before list"),
                        ["type": "list", "content": [listItem("first item"), listItem("second item")]]
                    ])

                    expect(fulltext(structure, [0])).to(equal("before list"))
                    expect(fulltext(structure, [1])).to(equal("first item\nsecond item"))
                }

                it("keeps separators when selected pages split sibling children of one container") {
                    let structure = document(pages: [[[0, 0], [0, 1]], [[0, 1], [0, 2]]], content: [
                        ["type": "list", "content": [listItem("first item"), listItem("second item")]]
                    ])

                    expect(fulltext(structure, [0])).to(equal("first item"))
                    expect(fulltext(structure, [1])).to(equal("second item"))
                    expect(fulltext(structure, [0, 1])).to(equal("first item\nsecond item"))
                }

                it("emits nested continuation chains once") {
                    let structure = document(pages: [[[0], [2]]], content: [
                        ["type": "list", "content": [listItem("programming", nextPart: [1, 0])]],
                        ["type": "list", "content": [listItem("and is used", previousPart: [0, 0])]]
                    ])

                    expect(fulltext(structure, [0])).to(equal("programming and is used"))
                }

                it("respects text-offset page boundaries") {
                    let structure = document(pages: [[[0, 0, 0], [0, 0, 3]], [[0, 0, 3], [0, 0, 6]]], content: [paragraph("abcdef")])

                    expect(fulltext(structure, [0])).to(equal("abc"))
                    expect(fulltext(structure, [1])).to(equal("def"))
                    expect(fulltext(structure, [0, 1])).to(equal("abcdef"))
                    expect(fulltext(structure, [1, 0])).to(equal("defabc"))
                }

                it("respects text-offset boundaries across multiple blocks") {
                    let structure = document(pages: [[[0, 0, 1], [2, 0, 2]]], content: [paragraph("abc"), paragraph("def"), paragraph("ghi")])

                    expect(fulltext(structure, [0])).to(equal("bc\n\ndef\n\ngh"))
                }

                it("treats equal boundaries as known empty pages") {
                    let structure = document(pages: [[[0], [0]], [[0], [1]], [[1], [1]]], content: [paragraph("visible")])

                    expect(fulltext(structure, [0])).to(equal(""))
                    expect(fulltext(structure, [1])).to(equal("visible"))
                    expect(fulltext(structure, [2])).to(equal(""))
                }

                for fixture in ["1_epub", "1_advanced_epub", "2_epub", "2_advanced_epub", "3_epub", "1_html"] {
                    it("produces expected full text for \(fixture)") {
                        let structure = loadStructure(named: "\(fixture)_structured_text")
                        let pageCount = ((structure["catalog"] as? [String: Any])?["pages"] as? [Any])?.count ?? 0
                        let expectedURL = Bundle(for: SDTContentSpec.self).url(forResource: "\(fixture)_fulltext", withExtension: "txt")!
                        let expected = Array(try String(contentsOf: expectedURL, encoding: .utf8).utf16)

                        let result = SDTFulltext.fulltext(from: structure, pageIndexes: Array(0..<pageCount))

                        // Compared as UTF-16 code units, since `String` equality ignores differences in Unicode normalization.
                        expect(result.count).to(equal(expected.count))
                        expect(result == expected).to(beTrue())
                    }
                }
            }

            describe("part chains") {
                it("follows previous parts to the root and stops at the first excluded part") {
                    let structure = document(pages: [], content: [
                        paragraph("one", nextPart: [1]),
                        paragraph("two", previousPart: [0], nextPart: [2]),
                        ["type": "paragraph", "flowClass": "excluded", "previousPart": [1], "content": [["text": "three"]]]
                    ])

                    let chain = SDTContent.partChain(in: structure, ref: [1], include: { _, node in (node["flowClass"] as? String) != "excluded" })

                    expect(chain.map(\.ref)).to(equal([[0], [1]]))
                }

                it("separates words with a space and nothing else") {
                    expect(separator("end", "start")).to(equal(" "))
                    expect(separator("end.", "start")).to(equal(""))
                    expect(separator("end ", "start")).to(equal(""))
                    expect(separator("end", " start")).to(equal(""))
                    expect(separator("число", "δέκα")).to(equal(" "))
                    expect(separator("42", "7")).to(equal(" "))
                }
            }
        }

        func fulltext(_ structure: [String: Any], _ pageIndexes: [Int]) -> String {
            return String(decoding: SDTFulltext.fulltext(from: structure, pageIndexes: pageIndexes), as: UTF16.self)
        }

        func separator(_ previous: String, _ next: String) -> String {
            let units = SDTContent.partBoundarySeparator(previousBlock: paragraph(previous), nextBlock: paragraph(next))
            return String(decoding: units, as: UTF16.self)
        }

        func document(pages: [[[Int]]], content: [[String: Any]]) -> [String: Any] {
            return ["catalog": ["pages": pages.map({ ["contentRange": $0] })], "content": content]
        }

        func paragraph(_ text: String, previousPart: [Int]? = nil, nextPart: [Int]? = nil) -> [String: Any] {
            var block: [String: Any] = ["type": "paragraph", "content": [["text": text]]]
            block["previousPart"] = previousPart
            block["nextPart"] = nextPart
            return block
        }

        func listItem(_ text: String, previousPart: [Int]? = nil, nextPart: [Int]? = nil) -> [String: Any] {
            var block = paragraph(text, previousPart: previousPart, nextPart: nextPart)
            block["type"] = "listitem"
            return block
        }

        func loadStructure(named name: String) -> [String: Any] {
            let url = Bundle(for: SDTContentSpec.self).url(forResource: name, withExtension: "json")!
            let data = try! Data(contentsOf: url)
            return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        }
    }
}
