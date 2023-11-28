//
//  EmojiExtractorSpec.swift
//  ZoteroTests
//
//  Created by Michal Rentka on 23.11.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

@testable import Zotero

import Nimble
import Quick

final class EmojiExtractorSpec: QuickSpec {
    override class func spec() {
        describe("emoji exctractor") {
            it("should return first emoji span") {
                expect(EmojiExtractor.extractFirstContiguousGroup(from: "🐩🐩🐩  🐩🐩🐩🐩")).to(equal("🐩🐩🐩"))
            }

            it("should return first emoji span") {
                expect(EmojiExtractor.extractFirstContiguousGroup(from: "./'!@#$ 🐩🐩🐩  🐩🐩🐩🐩")).to(equal("🐩🐩🐩"))
            }

            it("should return first emoji span") {
                expect(EmojiExtractor.extractFirstContiguousGroup(from: "Here are ⭐️⭐️⭐️⭐️⭐️")).to(equal("⭐️⭐️⭐️⭐️⭐️"))
            }

            it("should return first emoji span") {
                expect(EmojiExtractor.extractFirstContiguousGroup(from: "We are 👨‍🌾👨‍🌾. And I am a 👨‍🏫.")).to(equal("👨‍🌾👨‍🌾"))
            }
        }
    }
}
