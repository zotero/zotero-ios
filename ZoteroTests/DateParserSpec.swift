//
//  DateParserSpec.swift
//  ZoteroTests
//
//  Created by Michal Rentka on 28/05/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

@testable import Zotero

import Nimble
import Quick

final class DateParserSpec: QuickSpec {
    override class func spec() {
        describe("a date parser") {
            let parser = DateParser()
            
            it("returns nil for empty string") {
                expect(parser.parse(string: "")).to(beNil())
            }
            
            it("returns nil for blank string") {
                expect(parser.parse(string: " ")).to(beNil())
            }
            
            it("should parse string with just number <= 12 as month") {
                let date = parser.parse(string: "1")
                expect(date?.day).to(equal(0))
                expect(date?.month).to(equal(1))
                expect(date?.year).to(equal(0))
                expect(date?.order).to(equal("m"))
            }
            
            it("should parse string with just number > 12 and <= 31 as day") {
                let date = parser.parse(string: "30")
                expect(date?.day).to(equal(30))
                expect(date?.month).to(equal(0))
                expect(date?.year).to(equal(0))
                expect(date?.order).to(equal("d"))
            }
            
            it("should parse string with just number > 100 as year") {
                let date = parser.parse(string: "2020")
                expect(date?.day).to(equal(0))
                expect(date?.month).to(equal(0))
                expect(date?.year).to(equal(2020))
                expect(date?.order).to(equal("y"))
            }
            
            it("should parse three- and four-digit dates with leading zeros") {
                expect(parser.parse(string: "001")?.year).to(equal(1))
                expect(parser.parse(string: "0001")?.year).to(equal(1))
                expect(parser.parse(string: "012")?.year).to(equal(12))
                expect(parser.parse(string: "0012")?.year).to(equal(12))
                expect(parser.parse(string: "0123")?.year).to(equal(123))
            }
            
            it("should parse two-digit year greater than current year as previous century") {
                expect(parser.parse(string: "1/1/99")?.year).to(equal(1999))
            }
            
            it("should parse two-digit year less than or equal to current year as current century") {
                expect(parser.parse(string: "1/1/01")?.year).to(equal(2001))
                expect(parser.parse(string: "1/1/11")?.year).to(equal(2011))
            }
            
            it("should parse one-digit month and four-digit year") {
                let date = parser.parse(string: "8/2020")
                expect(date?.day).to(equal(0))
                expect(date?.month).to(equal(8))
                expect(date?.year).to(equal(2020))
                expect(date?.order).to(equal("my"))
            }
            
            it("should parse two-digit month with leading zero and four-digit year") {
                let date = parser.parse(string: "08/2020")
                expect(date?.day).to(equal(0))
                expect(date?.month).to(equal(8))
                expect(date?.year).to(equal(2020))
                expect(date?.order).to(equal("my"))
            }
            
            it("should parse month written as word") {
                let date = parser.parse(string: "January 2020")
                expect(date?.day).to(equal(0))
                expect(date?.month).to(equal(1))
                expect(date?.year).to(equal(2020))
                expect(date?.order).to(equal("my"))
            }
            
            it("should parse day with suffix") {
                let date = parser.parse(string: "20th January 2020")
                expect(date?.day).to(equal(20))
                expect(date?.month).to(equal(1))
                expect(date?.year).to(equal(2020))
                expect(date?.order).to(equal("dmy"))
            }
        }
    }
}
