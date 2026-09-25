//
//  TextTokenizerSpec.swift
//  ZoteroTests
//
//  Created by Michal Rentka on 2025.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import NaturalLanguage

@testable import Zotero

import Nimble
import Quick

final class TextTokenizerSpec: QuickSpec {
    override class func spec() {
        describe("TextTokenizer") {
            describe("findSentence") {
                it("finds first sentence from start") {
                    let text = "First sentence. Second sentence."
                    let result = TextTokenizer.findSentence(startingAt: 0, in: text)

                    expect(result).notTo(beNil())
                    expect(result?.text).to(equal("First sentence."))
                }

                it("finds remaining string from current sentence") {
                    let text = "First sentence. Second sentence."
                    let result = TextTokenizer.findSentence(startingAt: 3, in: text)

                    expect(result).notTo(beNil())
                    expect(result?.text).to(equal("st sentence."))
                }

                it("finds second sentence after first") {
                    let text = "First sentence. Second sentence."
                    let result = TextTokenizer.findSentence(startingAt: 16, in: text)

                    expect(result).notTo(beNil())
                    expect(result?.text).to(equal("Second sentence."))
                }

                it("handles multiple sentences in a paragraph") {
                    let text = "One. Two. Three."

                    let first = TextTokenizer.findSentence(startingAt: 0, in: text)
                    expect(first?.text).to(equal("One."))

                    let second = TextTokenizer.findSentence(startingAt: first!.range.location + first!.range.length, in: text)
                    expect(second?.text).to(equal("Two."))

                    let third = TextTokenizer.findSentence(startingAt: second!.range.location + second!.range.length, in: text)
                    expect(third?.text).to(equal("Three."))
                }

                it("returns nil when starting past end of text") {
                    let text = "First sentence."
                    let result = TextTokenizer.findSentence(startingAt: 100, in: text)

                    expect(result).to(beNil())
                }

                it("returns nil for empty text") {
                    let result = TextTokenizer.findSentence(startingAt: 0, in: "")

                    expect(result).to(beNil())
                }

                it("returns nil for whitespace-only text") {
                    let result = TextTokenizer.findSentence(startingAt: 0, in: "   \n\n   ")

                    expect(result).to(beNil())
                }

                it("handles text with leading whitespace") {
                    let text = "   \n\nFirst sentence."
                    let result = TextTokenizer.findSentence(startingAt: 0, in: text)

                    expect(result).notTo(beNil())
                    expect(result?.text).to(equal("First sentence."))
                }

                it("handles text without ending punctuation") {
                    let text = "Some text without punctuation"
                    let result = TextTokenizer.findSentence(startingAt: 0, in: text)

                    expect(result).notTo(beNil())
                    expect(result?.text).to(equal("Some text without punctuation"))
                }

                context("long sentence splitting") {
                    it("splits sentence with footnote number after period") {
                        let text = "This is a sentence.5 Another sentence here."
                        let result = TextTokenizer.findSentence(startingAt: 0, in: text)

                        expect(result).notTo(beNil())
                        expect(result?.text).to(equal("This is a sentence.5"))
                        expect(result?.range.length).to(equal(21)) // "This is a sentence.5 " is 21 characters (includes trailing space)
                    }

                    it("does not split abbreviations like U.S.") {
                        let text = "The U.S. government announced new policies."
                        let result = TextTokenizer.findSentence(startingAt: 0, in: text)

                        expect(result).notTo(beNil())
                        expect(result?.text).to(equal(text))
                    }

                    it("does not split short sentences") {
                        let text = "Short sentence."
                        let result = TextTokenizer.findSentence(startingAt: 0, in: text)

                        expect(result).notTo(beNil())
                        expect(result?.text).to(equal("Short sentence."))
                    }

                    it("splits very long sentence at natural break point") {
                        // Create a sentence longer than maxSentenceLength with a period+digit pattern
                        let longText = String(repeating: "word ", count: 60) + "end.1 More text here."
                        let result = TextTokenizer.findSentence(startingAt: 0, in: longText)

                        expect(result).notTo(beNil())
                        expect(result?.text.hasSuffix("end.1")).to(beTrue())
                        expect(result?.text.count).to(beLessThanOrEqualTo(TextTokenizer.maxSentenceLength))
                    }

                    it("splits at last space when no natural break point exists") {
                        // Create a very long sentence with no period+digit pattern
                        let longText = String(repeating: "word ", count: 100) + "ending"
                        let result = TextTokenizer.findSentence(startingAt: 0, in: longText)

                        expect(result).notTo(beNil())
                        expect(result?.text.count).to(beLessThanOrEqualTo(TextTokenizer.maxSentenceLength))
                        // Should end at a word boundary (no partial words)
                        expect(result?.text.hasSuffix("word")).to(beTrue())
                    }

                    it("iterates through text with footnotes correctly") {
                        let text = "First sentence.1 Second sentence.2 Third sentence."

                        let first = TextTokenizer.findSentence(startingAt: 0, in: text)
                        expect(first?.text).to(equal("First sentence.1"))

                        let second = TextTokenizer.findSentence(startingAt: first!.range.location + first!.range.length, in: text)
                        expect(second?.text).to(equal("Second sentence.2"))

                        let third = TextTokenizer.findSentence(startingAt: second!.range.location + second!.range.length, in: text)
                        expect(third?.text).to(equal("Third sentence."))
                    }

                    it("handles exclamation mark followed by digit") {
                        let text = "Amazing discovery!5 The research continues."
                        let result = TextTokenizer.findSentence(startingAt: 0, in: text)

                        expect(result).notTo(beNil())
                        expect(result?.text).to(equal("Amazing discovery!5"))
                    }

                    it("handles question mark followed by digit") {
                        let text = "Is this true?5 Yes it is."
                        let result = TextTokenizer.findSentence(startingAt: 0, in: text)

                        expect(result).notTo(beNil())
                        expect(result?.text).to(equal("Is this true?5"))
                    }
                }
            }

            describe("nextSentenceStart") {
                context("with sentences") {
                    it("finds start of next sentence from end of current") {
                        let text = "First sentence. Second sentence."
                        // After reading "First sentence. " (positions 0..16), forward starts at 16
                        let result = TextTokenizer.nextSentenceStart(after: 16, in: text)

                        expect(result).notTo(beNil())
                        expect(result).to(equal(16)) // Start of "Second sentence."
                    }

                    it("returns end of current sentence when starting in the middle") {
                        let text = "First sentence. Second sentence. Third."
                        let result = TextTokenizer.nextSentenceStart(after: 5, in: text)

                        expect(result).notTo(beNil())
                        expect(result).to(equal(16))
                    }

                    it("returns startIndex when at start of a sentence") {
                        let text = "First. Second. Third."
                        // Position 7 is the start of "Second." — must not skip past it
                        let result = TextTokenizer.nextSentenceStart(after: 7, in: text)

                        expect(result).notTo(beNil())
                        expect(result).to(equal(7))
                    }

                    it("returns nil when starting past end of text") {
                        let text = "First sentence."
                        let result = TextTokenizer.nextSentenceStart(after: 100, in: text)

                        expect(result).to(beNil())
                    }

                    it("returns nil for empty text") {
                        let result = TextTokenizer.nextSentenceStart(after: 0, in: "")

                        expect(result).to(beNil())
                    }

                    it("returns nil for whitespace-only text") {
                        let result = TextTokenizer.nextSentenceStart(after: 0, in: "   \n\n   ")

                        expect(result).to(beNil())
                    }
                }
            }

            describe("findSentenceContaining") {
                it("finds sentence containing index with footnotes") {
                    let text = "First sentence.5 Second sentence.2 Third sentence."
                    // Index in "Second" (position 17)
                    let result = TextTokenizer.findSentenceContaining(index: 17, in: text)

                    expect(result).notTo(beNil())
                    // Should return the full second sentence chunk including footnote digits
                    expect(result?.text).to(contain("Second sentence"))
                }

                it("finds first sentence containing index at start") {
                    let text = "First sentence.5 Second sentence."
                    let result = TextTokenizer.findSentenceContaining(index: 3, in: text)

                    expect(result).notTo(beNil())
                    expect(result?.text).to(contain("First sentence"))
                }
            }

            describe("nextSentenceStart with footnotes") {
                it("finds next sentence index past footnote") {
                    let text = "First sentence.5 Second sentence."
                    // After reading "First sentence.5 " (positions 0..17), forward starts at 17
                    let result = TextTokenizer.nextSentenceStart(after: 17, in: text)

                    expect(result).notTo(beNil())
                    expect(result).to(equal(17)) // Start of "Second sentence."
                }
            }

            describe("previousSentenceStart with footnotes") {
                it("finds previous sentence start past footnote") {
                    let text = "First sentence.5 Second sentence.2 Third sentence."
                    // From end of text, should find start of last sentence
                    let result = TextTokenizer.previousSentenceStart(before: text.count, in: text)

                    expect(result).notTo(beNil())
                }

                it("finds previous sentence when footnote is followed by newline") {
                    let text = "Test sentence.5\nNext sentence"
                    // beforeIndex 18 is inside "Next sentence", should return 0 (start of first sentence)
                    let result = TextTokenizer.previousSentenceStart(before: 18, in: text)

                    expect(result).notTo(beNil())
                    expect(result).to(equal(0))
                }
            }

            describe("findSentence with footnote and newline") {
                it("returns sentence text including footnote digit") {
                    let text = "Test sentence.5\nNext sentence."
                    let result = TextTokenizer.findSentence(startingAt: 0, in: text)

                    expect(result).notTo(beNil())
                    expect(result?.text).to(equal("Test sentence.5"))
                }
            }

            describe("normalization edge cases") {
                it("does not break decimal numbers") {
                    let text = "The value is 3.5 and it matters."
                    let result = TextTokenizer.findSentence(startingAt: 0, in: text)

                    expect(result).notTo(beNil())
                    expect(result?.text).to(equal("The value is 3.5 and it matters."))
                }

                it("handles multi-digit footnotes") {
                    let text = "Important claim.12 Next sentence."
                    let result = TextTokenizer.findSentence(startingAt: 0, in: text)

                    expect(result).notTo(beNil())
                    expect(result?.text).to(equal("Important claim.12"))
                }

                it("handles closing quote before footnote") {
                    let text = "He said \"hello.\"5 Next sentence."
                    let result = TextTokenizer.findSentence(startingAt: 0, in: text)

                    expect(result).notTo(beNil())
                    // The quote+period+digit pattern should be normalized
                    expect(result?.text.count).to(beLessThan(text.count))
                }

                it("handles closing parenthesis before footnote") {
                    let text = "Some claim (see above).5 More text here."
                    let result = TextTokenizer.findSentence(startingAt: 0, in: text)

                    expect(result).notTo(beNil())
                    expect(result?.text).to(equal("Some claim (see above).5"))
                }

                it("handles closing bracket before footnote") {
                    let text = "Reference [1].5 Another sentence."
                    let result = TextTokenizer.findSentence(startingAt: 0, in: text)

                    expect(result).notTo(beNil())
                    expect(result?.text).to(equal("Reference [1].5"))
                }
            }

            describe("previousSentenceStart") {
                context("with sentences") {
                    it("finds previous sentence when in middle of current") {
                        let text = "First. Second. Third."
                        // Position in middle of "Third" (index 17)
                        let result = TextTokenizer.previousSentenceStart(before: 17, in: text)

                        expect(result).notTo(beNil())
                        expect(result).to(equal(7)) // Start of "Second"
                    }

                    it("finds previous sentence when at start of current") {
                        let text = "First. Second. Third."
                        // Position at start of "Third" (index 15)
                        let result = TextTokenizer.previousSentenceStart(before: 15, in: text)

                        expect(result).notTo(beNil())
                        expect(result).to(equal(7)) // Start of "Second"
                    }

                    it("returns nil when in first sentence") {
                        let text = "First. Second."
                        // Position in middle of first sentence
                        let result = TextTokenizer.previousSentenceStart(before: 3, in: text)

                        expect(result).to(beNil())
                    }
                }
            }
        }
    }
}
