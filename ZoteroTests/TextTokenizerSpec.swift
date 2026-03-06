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
                        expect(result?.text).to(equal("This is a sentence."))
                        expect(result?.range.length).to(equal(19)) // "This is a sentence." is 19 characters
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
                        expect(result?.text.hasSuffix("end.")).to(beTrue())
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
                        expect(first?.text).to(equal("First sentence."))

                        let second = TextTokenizer.findSentence(startingAt: first!.range.location + first!.range.length, in: text)
                        expect(second?.text).to(equal("1 Second sentence."))

                        let third = TextTokenizer.findSentence(startingAt: second!.range.location + second!.range.length, in: text)
                        expect(third?.text).to(equal("2 Third sentence."))
                    }

                    it("handles exclamation mark followed by digit") {
                        let text = "Amazing discovery!5 The research continues."
                        let result = TextTokenizer.findSentence(startingAt: 0, in: text)

                        expect(result).notTo(beNil())
                        expect(result?.text).to(equal("Amazing discovery!"))
                    }

                    it("handles question mark followed by digit") {
                        let text = "Is this true?5 Yes it is."
                        let result = TextTokenizer.findSentence(startingAt: 0, in: text)

                        expect(result).notTo(beNil())
                        expect(result?.text).to(equal("Is this true?"))
                    }
                }
            }

            describe("findIndex ofNext") {
                context("with sentences") {
                    it("finds index of next sentence from start") {
                        let text = "First sentence. Second sentence."
                        let result = TextTokenizer.findIndex(ofNext: .sentence, startingAt: 0, in: text)

                        expect(result).notTo(beNil())
                        expect(result).to(equal(16)) // Position after "First sentence. "
                    }

                    it("finds index of next sentence from middle of current") {
                        let text = "First sentence. Second sentence. Third."
                        // Start from middle of first sentence
                        let result = TextTokenizer.findIndex(ofNext: .sentence, startingAt: 5, in: text)

                        // Should return end of current partial sentence
                        expect(result).notTo(beNil())
                        expect(result).to(equal(16))
                    }

                    it("finds index of next sentence after second") {
                        let text = "First. Second. Third."
                        let result = TextTokenizer.findIndex(ofNext: .sentence, startingAt: 7, in: text)

                        expect(result).notTo(beNil())
                        expect(result).to(equal(15)) // Position after "Second. "
                    }

                    it("returns nil when starting past end of text") {
                        let text = "First sentence."
                        let result = TextTokenizer.findIndex(ofNext: .sentence, startingAt: 100, in: text)

                        expect(result).to(beNil())
                    }

                    it("returns nil for empty text") {
                        let result = TextTokenizer.findIndex(ofNext: .sentence, startingAt: 0, in: "")

                        expect(result).to(beNil())
                    }

                    it("returns nil for whitespace-only text") {
                        let result = TextTokenizer.findIndex(ofNext: .sentence, startingAt: 0, in: "   \n\n   ")

                        expect(result).to(beNil())
                    }
                }

                context("with paragraphs") {
                    it("finds index of next paragraph from start") {
                        let text = "First paragraph.\n\nSecond paragraph."
                        let result = TextTokenizer.findIndex(ofNext: .paragraph, startingAt: 0, in: text)

                        expect(result).notTo(beNil())
                        expect(result).to(equal(18)) // Position after "First paragraph.\n\n"
                    }

                    it("finds index of next paragraph after second") {
                        let text = "Para 1.\n\nPara 2.\n\nPara 3."
                        let result = TextTokenizer.findIndex(ofNext: .paragraph, startingAt: 9, in: text)

                        expect(result).notTo(beNil())
                        expect(result).to(equal(18)) // Position after "Para 2.\n\n"
                    }

                    it("allows stepping forward through paragraphs") {
                        let text = "Para 1.\n\nPara 2.\n\nPara 3.\n\nPara 4."

                        var index = 0

                        // First forward: skip Para 1, should go to start of Para 2
                        if let nextIndex = TextTokenizer.findIndex(ofNext: .paragraph, startingAt: index, in: text) {
                            index = nextIndex
                            expect(index).to(equal(9))
                        }

                        // Second forward: skip Para 2, should go to start of Para 3
                        if let nextIndex = TextTokenizer.findIndex(ofNext: .paragraph, startingAt: index, in: text) {
                            index = nextIndex
                            expect(index).to(equal(18))
                        }

                        // Third forward: skip Para 3, should go to start of Para 4
                        if let nextIndex = TextTokenizer.findIndex(ofNext: .paragraph, startingAt: index, in: text) {
                            index = nextIndex
                            expect(index).to(equal(27))
                        }

                        // Fourth forward: at Para 4, should return nil (no more paragraphs)
                        let result = TextTokenizer.findIndex(ofNext: .paragraph, startingAt: index, in: text)
                        expect(result).to(equal(text.count))
                    }
                }
            }
            
            describe("find previous index") {
                context("with paragraphs") {
                    it("finds previous paragraph when in middle of current") {
                        let text = "First paragraph.\n\nSecond paragraph.\n\nThird paragraph."
                        // Position in middle of second paragraph (index 25)
                        let result = TextTokenizer.findIndex(ofPreviousWhole: .paragraph, beforeIndex: 25, in: text)
                        
                        expect(result).notTo(beNil())
                        expect(result).to(equal(0)) // Start of first paragraph
                    }
                    
                    it("finds previous paragraph when at start of current") {
                        let text = "First paragraph.\n\nSecond paragraph.\n\nThird paragraph."
                        // Position at start of third paragraph (index 37)
                        let result = TextTokenizer.findIndex(ofPreviousWhole: .paragraph, beforeIndex: 37, in: text)
                        
                        expect(result).notTo(beNil())
                        expect(result).to(equal(18)) // Start of second paragraph
                    }
                    
                    it("returns current paragraph when at end of it") {
                        let text = "First paragraph.\n\nSecond paragraph.\n\nThird paragraph."
                        // Position at end of text (end of third paragraph)
                        let result = TextTokenizer.findIndex(ofPreviousWhole: .paragraph, beforeIndex: text.count, in: text)
                        
                        expect(result).notTo(beNil())
                        expect(result).to(equal(37)) // Start of third paragraph
                    }
                    
                    it("returns first paragraph when at start of second") {
                        let text = "First paragraph.\n\nSecond paragraph."
                        // Position at start of second paragraph
                        let result = TextTokenizer.findIndex(ofPreviousWhole: .paragraph, beforeIndex: 18, in: text)
                        
                        expect(result).notTo(beNil())
                        expect(result).to(equal(0)) // Start of first paragraph
                    }
                    
                    it("returns nil when in middle of first paragraph") {
                        let text = "First paragraph.\n\nSecond paragraph."
                        // Position in middle of first paragraph
                        let result = TextTokenizer.findIndex(ofPreviousWhole: .paragraph, beforeIndex: 5, in: text)
                        
                        expect(result).to(beNil())
                    }
                    
                    it("returns nil when index is 0") {
                        let text = "First paragraph."
                        let result = TextTokenizer.findIndex(ofPreviousWhole: .paragraph, beforeIndex: 0, in: text)
                        
                        expect(result).to(beNil())
                    }
                    
                    it("returns nil for empty text") {
                        let result = TextTokenizer.findIndex(ofPreviousWhole: .paragraph, beforeIndex: 0, in: "")
                        
                        expect(result).to(beNil())
                    }
                    
                    it("returns nil when only whitespace before index") {
                        let text = "   \n\n   First paragraph."
                        let result = TextTokenizer.findIndex(ofPreviousWhole: .paragraph, beforeIndex: 5, in: text)
                        
                        expect(result).to(beNil())
                    }
                }
                
                context("with sentences") {
                    it("finds previous sentence when in middle of current") {
                        let text = "First. Second. Third."
                        // Position in middle of "Third" (index 17)
                        let result = TextTokenizer.findIndex(ofPreviousWhole: .sentence, beforeIndex: 17, in: text)
                        
                        expect(result).notTo(beNil())
                        expect(result).to(equal(7)) // Start of "Second"
                    }
                    
                    it("finds previous sentence when at start of current") {
                        let text = "First. Second. Third."
                        // Position at start of "Third" (index 15)
                        let result = TextTokenizer.findIndex(ofPreviousWhole: .sentence, beforeIndex: 15, in: text)
                        
                        expect(result).notTo(beNil())
                        expect(result).to(equal(7)) // Start of "Second"
                    }
                    
                    it("returns nil when in first sentence") {
                        let text = "First. Second."
                        // Position in middle of first sentence
                        let result = TextTokenizer.findIndex(ofPreviousWhole: .sentence, beforeIndex: 3, in: text)
                        
                        expect(result).to(beNil())
                    }
                }
                
                context("navigation behavior") {
                    it("allows stepping back through multiple paragraphs from end") {
                        let text = "Para 1.\n\nPara 2.\n\nPara 3.\n\nPara 4."
                        
                        // Start from end - should find Para 4
                        var index = text.count
                        
                        // First backward from end: should go to start of Para 4
                        if let prevIndex = TextTokenizer.findIndex(ofPreviousWhole: .paragraph, beforeIndex: index, in: text) {
                            index = prevIndex
                            expect(index).to(equal(27)) // Start of "Para 4"
                        }
                        
                        // Second backward: should go to Para 3
                        if let prevIndex = TextTokenizer.findIndex(ofPreviousWhole: .paragraph, beforeIndex: index, in: text) {
                            index = prevIndex
                            expect(index).to(equal(18)) // Start of "Para 3"
                        }
                        
                        // Third backward: should go to Para 2
                        if let prevIndex = TextTokenizer.findIndex(ofPreviousWhole: .paragraph, beforeIndex: index, in: text) {
                            index = prevIndex
                            expect(index).to(equal(9)) // Start of "Para 2"
                        }
                        
                        // Fourth backward: should go to Para 1
                        if let prevIndex = TextTokenizer.findIndex(ofPreviousWhole: .paragraph, beforeIndex: index, in: text) {
                            index = prevIndex
                            expect(index).to(equal(0)) // Start of "Para 1"
                        }
                        
                        // Fifth backward: should return nil (no more paragraphs)
                        let result = TextTokenizer.findIndex(ofPreviousWhole: .paragraph, beforeIndex: index, in: text)
                        expect(result).to(beNil())
                    }
                }
            }
        }
    }
}
