//
//  HtmlAttributedStringConverterSpec.swift
//  ZoteroTests
//
//  Created by Michal Rentka on 12.07.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

@testable import Zotero

import Nimble
import Quick

final class HtmlAttributedStringConverterSpec: QuickSpec {
    override class func spec() {
        let font = UIFont.preferredFont(forTextStyle: .body)
        let htmlConverter = HtmlAttributedStringConverter()

        describe("conversion from String to NSAttributedString") {
            it("converts b tag") {
                let text = "pretext <b>text</b> posttext"
                let attributedString = htmlConverter.convert(text: text, baseAttributes: [.font: font])
                var count = 0

                attributedString.enumerateAttributes(in: NSRange(location: 0, length: attributedString.length), options: []) { nsAttributes, range, _ in
                    if range.location == 8 && range.length == 4 {
                        expect(StringAttribute.attributes(from: nsAttributes)).to(equal([.bold]))
                    }
                    count += 1
                }

                expect(count).to(equal(3))
            }

            it("converts i tag") {
                let text = "pretext <i>text</i> posttext"
                let attributedString = htmlConverter.convert(text: text, baseAttributes: [.font: font])
                var count = 0

                attributedString.enumerateAttributes(in: NSRange(location: 0, length: attributedString.length), options: []) { nsAttributes, range, _ in
                    if range.location == 8 && range.length == 4 {
                        expect(StringAttribute.attributes(from: nsAttributes)).to(equal([.italic]))
                    }
                    count += 1
                }

                expect(count).to(equal(3))
            }

            it("converts sub tag") {
                let text = "pretext <sub>text</sub> posttext"
                let attributedString = htmlConverter.convert(text: text, baseAttributes: [.font: font])
                var count = 0

                attributedString.enumerateAttributes(in: NSRange(location: 0, length: attributedString.length), options: []) { nsAttributes, range, _ in
                    if range.location == 8 && range.length == 4 {
                        expect(StringAttribute.attributes(from: nsAttributes)).to(equal([.subscript]))
                    }
                    count += 1
                }

                expect(count).to(equal(3))
            }

            it("converts sup tag") {
                let text = "pretext <sup>text</sup> posttext"
                let attributedString = htmlConverter.convert(text: text, baseAttributes: [.font: font])
                var count = 0

                attributedString.enumerateAttributes(in: NSRange(location: 0, length: attributedString.length), options: []) { nsAttributes, range, _ in
                    if range.location == 8 && range.length == 4 {
                        expect(StringAttribute.attributes(from: nsAttributes)).to(equal([.superscript]))
                    }
                    count += 1
                }

                expect(count).to(equal(3))
            }

            it("converts smallcaps tag") {
                let text = #"pretext <span style="font-variant:small-caps;">text</span> posttext"#
                let attributedString = htmlConverter.convert(text: text, baseAttributes: [.font: font])
                var count = 0

                attributedString.enumerateAttributes(in: NSRange(location: 0, length: attributedString.length), options: []) { nsAttributes, range, _ in
                    if range.location == 8 && range.length == 4 {
                        expect(StringAttribute.attributes(from: nsAttributes)).to(equal([.smallcaps]))
                    }
                    count += 1
                }

                expect(count).to(equal(3))
            }

            it("converts multiple tags") {
                let text = #"abc <i><b>def</b></i> ghi <span style="font-variant:small-caps;">jk<sup>l</sup></span> mno"#
                let attributedString = htmlConverter.convert(text: text, baseAttributes: [.font: font])
                var remaining: Set<StringAttribute> = [.bold, .italic, .smallcaps, .superscript]
                var count = 0

                attributedString.enumerateAttributes(in: NSRange(location: 0, length: attributedString.length), options: []) { nsAttributes, range, _ in
                    if range.location == 4 && range.length == 3 {
                        expect(StringAttribute.attributes(from: nsAttributes)).to(equal([.bold, .italic]))
                        remaining.remove(.bold)
                        remaining.remove(.italic)
                    }
                    if range.location == 12 && range.length == 2 {
                        expect(StringAttribute.attributes(from: nsAttributes)).to(equal([.smallcaps]))
                        remaining.remove(.smallcaps)
                    }
                    if range.location == 14 && range.length == 1 {
                        expect(StringAttribute.attributes(from: nsAttributes)).to(equal([.smallcaps, .superscript]))
                        remaining.remove(.superscript)
                    }
                    count += 1
                }

                expect(remaining).to(beEmpty())
                expect(count).to(equal(6))
            }
        }

        describe("conversion from NSAttributedString to String") {
            it("converts b tag") {
                let attributedString = NSMutableAttributedString(string: "pretext text posttext", attributes: [.font: font])
                attributedString.addAttributes(StringAttribute.nsStringAttributes(from: [.bold], baseFont: font), range: NSRange(location: 8, length: 4))
                let string = htmlConverter.convert(attributedString: attributedString)
                expect(string).to(equal("pretext <b>text</b> posttext"))
            }

            it("converts i tag") {
                let attributedString = NSMutableAttributedString(string: "pretext text posttext", attributes: [.font: font])
                attributedString.addAttributes(StringAttribute.nsStringAttributes(from: [.italic], baseFont: font), range: NSRange(location: 8, length: 4))
                let string = htmlConverter.convert(attributedString: attributedString)
                expect(string).to(equal("pretext <i>text</i> posttext"))
            }

            it("converts sub tag") {
                let attributedString = NSMutableAttributedString(string: "pretext text posttext", attributes: [.font: font])
                attributedString.addAttributes(StringAttribute.nsStringAttributes(from: [.subscript], baseFont: font), range: NSRange(location: 8, length: 4))
                let string = htmlConverter.convert(attributedString: attributedString)
                expect(string).to(equal("pretext <sub>text</sub> posttext"))
            }

            it("converts sup tag") {
                let attributedString = NSMutableAttributedString(string: "pretext text posttext", attributes: [.font: font])
                attributedString.addAttributes(StringAttribute.nsStringAttributes(from: [.superscript], baseFont: font), range: NSRange(location: 8, length: 4))
                let string = htmlConverter.convert(attributedString: attributedString)
                expect(string).to(equal("pretext <sup>text</sup> posttext"))
            }

            it("converts smallcaps tag") {
                let attributedString = NSMutableAttributedString(string: "pretext text posttext", attributes: [.font: font])
                attributedString.addAttributes(StringAttribute.nsStringAttributes(from: [.smallcaps], baseFont: font), range: NSRange(location: 8, length: 4))
                let string = htmlConverter.convert(attributedString: attributedString)
                expect(string).to(equal(#"pretext <span style="font-variant:small-caps;">text</span> posttext"#))
            }

            it("converts multiple tags") {
                let attributedString = NSMutableAttributedString(string: "abc def ghi jkl mno", attributes: [.font: font])
                attributedString.addAttributes(StringAttribute.nsStringAttributes(from: [.italic, .bold], baseFont: font), range: NSRange(location: 4, length: 3))
                attributedString.addAttributes(StringAttribute.nsStringAttributes(from: [.smallcaps], baseFont: font), range: NSRange(location: 12, length: 2))
                attributedString.addAttributes(StringAttribute.nsStringAttributes(from: [.smallcaps, .superscript], baseFont: font), range: NSRange(location: 14, length: 1))
                let string = htmlConverter.convert(attributedString: attributedString)
                expect(string).to(equal(#"abc <b><i>def</i></b> ghi <span style="font-variant:small-caps;">jk<sup>l</sup></span> mno"#))
            }
            
            it("converts multiple tags complex") {
                let attributedStringRaw = #"start_bold_italic_subscript bold bold_superscript bold bold_subscript bold bold\nitalic\nend"#
                let htmlStringRaw = #"<b><i><sub>start_bold_italic_subscript</sub></i> bold <sup>bold_superscript</sup> bold <sub>bold_subscript</sub> bold <i>bold\nitalic\nend</i></b>"#
                let attributesAndRanges: [([StringAttribute], NSRange)] = [
                    ([.bold, .italic, .subscript], NSRange(location: 0, length: 27)),
                    ([.bold], NSRange(location: 27, length: 6)),
                    ([.bold, .superscript], NSRange(location: 33, length: 16)),
                    ([.bold], NSRange(location: 49, length: 6)),
                    ([.bold, .subscript], NSRange(location: 55, length: 14)),
                    ([.bold], NSRange(location: 69, length: 6)),
                    ([.bold, .italic], NSRange(location: 75, length: 17))
                ]
                let attributedString = NSMutableAttributedString(string: attributedStringRaw, attributes: [.font: font])
                expect(attributedString.string.count).to(equal(attributedStringRaw.count))
                for (attributes, range) in attributesAndRanges {
                    attributedString.addAttributes(StringAttribute.nsStringAttributes(from: attributes, baseFont: font), range: range)
                }
                let string = htmlConverter.convert(attributedString: attributedString)
                expect(string).to(equal(htmlStringRaw))
            }

            it("converts attributed string with larger length than string count") {
                let attributedStringRawParts = [
                    #"This is bold\nas is this. "#,
                    #"Now it is not 😏😂😚👩🏿‍💻 but 2 lines down it is again\n\n"#,
                    #"    here that is 😏😂😚👩🏼‍💻   . \nThe end."#
                ]
                let attributedStringRaw = attributedStringRawParts.joined()
                let htmlStringRaw = "<b>" + attributedStringRawParts[0] + "</b>" + attributedStringRawParts[1] + "<b>" + attributedStringRawParts[2] + "</b>"
                let attributesAndRanges: [([StringAttribute], NSRange)] = [
                    ([.bold], NSRange(location: 0, length: NSAttributedString(string: attributedStringRawParts[0]).length)),
                    ([.bold], NSRange(
                        location: NSAttributedString(string: attributedStringRawParts[0] + attributedStringRawParts[1]).length,
                        length: NSAttributedString(string: attributedStringRawParts[2]).length)
                    )
                ]
                let attributedString = NSMutableAttributedString(string: attributedStringRaw, attributes: [.font: font])
                expect(attributedString.string.count).to(equal(attributedStringRaw.count))
                for (attributes, range) in attributesAndRanges {
                    attributedString.addAttributes(StringAttribute.nsStringAttributes(from: attributes, baseFont: font), range: range)
                }
                let string = htmlConverter.convert(attributedString: attributedString)
                expect(string).to(equal(htmlStringRaw))
            }

            it("resets subscript by toggling with title font") {
                // Edge case found during development, where there are consecutive ranges with the same attributes, due to the selected font.
                let font = UIFont.preferredFont(for: .headline, weight: .regular)
                let attributedStringRawParts = [
                    #"How"#,
                    #" "#,
                    #"Far"#,
                    #" Are We "#,
                    #"From"#,
                    #" AGI"#
                ]
                let attributedStringRaw = attributedStringRawParts.joined()
                var htmlStringRaw = ""
                htmlStringRaw += "<sup>" + attributedStringRawParts[0] + "</sup>"
                htmlStringRaw += attributedStringRawParts[1]
                htmlStringRaw += "<sub>" + attributedStringRawParts[2] + "</sub>"
                htmlStringRaw += attributedStringRawParts[3]
                htmlStringRaw += "<b>" + attributedStringRawParts[4] + "</b>"
                htmlStringRaw += attributedStringRawParts[5]
                let subscriptRange = NSRange(
                    location: NSAttributedString(string: attributedStringRawParts[0] + attributedStringRawParts[1]).length,
                    length: NSAttributedString(string: attributedStringRawParts[2]).length
                )
                let attributesAndRanges: [([StringAttribute], NSRange)] = [
                    ([.superscript], NSRange(location: 0, length: NSAttributedString(string: attributedStringRawParts[0]).length)),
                    ([.subscript], subscriptRange),
                    ([.bold], NSRange(
                        location: NSAttributedString(string: attributedStringRawParts[0] + attributedStringRawParts[1] + attributedStringRawParts[2] + attributedStringRawParts[3]).length,
                        length: NSAttributedString(string: attributedStringRawParts[4]).length
                    ))
                ]
                let attributedString = NSMutableAttributedString(string: attributedStringRaw, attributes: [.font: font])
                expect(attributedString.string.count).to(equal(attributedStringRaw.count))
                for (attributes, range) in attributesAndRanges {
                    attributedString.addAttributes(StringAttribute.nsStringAttributes(from: attributes, baseFont: font), range: range)
                }
                let string = htmlConverter.convert(attributedString: attributedString)
                expect(string).to(equal(htmlStringRaw))
                // Toggle subscript
                var newHtmlStringRaw = ""
                newHtmlStringRaw += "<sup>" + attributedStringRawParts[0] + "</sup>"
                newHtmlStringRaw += attributedStringRawParts[1]
                newHtmlStringRaw += attributedStringRawParts[2]
                newHtmlStringRaw += attributedStringRawParts[3]
                newHtmlStringRaw += "<b>" + attributedStringRawParts[4] + "</b>"
                newHtmlStringRaw += attributedStringRawParts[5]
                let newAttributedString = NSMutableAttributedString(attributedString: attributedString)
                StringAttribute.toggleSubscript(in: newAttributedString, range: subscriptRange, defaultFont: font)
                expect(newAttributedString.string.count).to(equal(attributedStringRaw.count))
                let newString = htmlConverter.convert(attributedString: newAttributedString)
                expect(newString).to(equal(newHtmlStringRaw))
            }
        }
    }
}
