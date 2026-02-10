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
            describe("find next") {
                context("with paragraphs") {
                    it("finds first paragraph from start") {
                        let text = "First paragraph.\n\nSecond paragraph."
                        let result = TextTokenizer.find(.paragraph, startingAt: 0, in: text)
                        
                        expect(result).notTo(beNil())
                        expect(result?.text).to(equal("First paragraph."))
                        expect(result?.range.location).to(equal(0))
                    }
                    
                    it("finds remaining string from current paragraph") {
                        let text = "First paragraph.\n\nSecond paragraph."
                        let result = TextTokenizer.find(.paragraph, startingAt: 3, in: text)
                        
                        expect(result).notTo(beNil())
                        expect(result?.text).to(equal("st paragraph."))
                    }
                    
                    it("finds second paragraph after first") {
                        let text = "First paragraph.\n\nSecond paragraph."
                        let result = TextTokenizer.find(.paragraph, startingAt: 18, in: text)
                        
                        expect(result).notTo(beNil())
                        expect(result?.text).to(equal("Second paragraph."))
                    }
                    
                    it("returns nil when starting past end of text") {
                        let text = "First paragraph."
                        let result = TextTokenizer.find(.paragraph, startingAt: 100, in: text)
                        
                        expect(result).to(beNil())
                    }
                    
                    it("returns nil for empty text") {
                        let result = TextTokenizer.find(.paragraph, startingAt: 0, in: "")
                        
                        expect(result).to(beNil())
                    }
                    
                    it("returns nil for whitespace-only text") {
                        let result = TextTokenizer.find(.paragraph, startingAt: 0, in: "   \n\n   ")
                        
                        expect(result).to(beNil())
                    }
                    
                    it("handles text with leading whitespace") {
                        let text = "   \n\nFirst paragraph."
                        let result = TextTokenizer.find(.paragraph, startingAt: 0, in: text)
                        
                        expect(result).notTo(beNil())
                        expect(result?.text).to(equal("First paragraph."))
                    }
                    
                    it("handles text without ending punctuation") {
                        let text = "Some text without punctuation"
                        let result = TextTokenizer.find(.paragraph, startingAt: 0, in: text)
                        
                        expect(result).notTo(beNil())
                        expect(result?.text).to(equal("Some text without punctuation"))
                    }
                }
                
                context("with sentences") {
                    it("finds first sentence from start") {
                        let text = "First sentence. Second sentence."
                        let result = TextTokenizer.find(.sentence, startingAt: 0, in: text)
                        
                        expect(result).notTo(beNil())
                        expect(result?.text).to(equal("First sentence."))
                    }
                    
                    it("finds remaining string from current sentence") {
                        let text = "First sentence. Second sentence."
                        let result = TextTokenizer.find(.sentence, startingAt: 3, in: text)
                        
                        expect(result).notTo(beNil())
                        expect(result?.text).to(equal("st sentence."))
                    }
                    
                    it("finds second sentence after first") {
                        let text = "First sentence. Second sentence."
                        let result = TextTokenizer.find(.sentence, startingAt: 16, in: text)
                        
                        expect(result).notTo(beNil())
                        expect(result?.text).to(equal("Second sentence."))
                    }
                    
                    it("handles multiple sentences in a paragraph") {
                        let text = "One. Two. Three."
                        
                        let first = TextTokenizer.find(.sentence, startingAt: 0, in: text)
                        expect(first?.text).to(equal("One."))
                        
                        let second = TextTokenizer.find(.sentence, startingAt: first!.range.location + first!.range.length, in: text)
                        expect(second?.text).to(equal("Two."))
                        
                        let third = TextTokenizer.find(.sentence, startingAt: second!.range.location + second!.range.length, in: text)
                        expect(third?.text).to(equal("Three."))
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
