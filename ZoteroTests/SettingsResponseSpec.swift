//
//  SettingsResponseSpec.swift
//  ZoteroTests
//
//  Created by Michal Rentka on 27.10.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

@testable import Zotero

import Nimble
import Quick

final class SettingsResponseSpec: QuickSpec {
    override class func spec() {
        describe("a JSON settings response") {
            var jsonData: [String: Any]!

            justBeforeEach {
                let json = """
                {
                    "lastPageIndex_u_ZYI76ILE": {
                        "value": 1,
                        "version": 62756
                    },
                    "lastPageIndex_u_ZYI76ILF": {
                        "value": 2.2,
                        "version": 62756
                    },
                    "lastPageIndex_u_ZYI76ILG": {
                        "value": 2.233412312,
                        "version": 62756
                    },
                    "lastPageIndex_g333_ZYI76ILH": {
                        "value": "asda",
                        "version": 62756
                    },
                    "tagColors": {
                        "value": [],
                        "version": 66099
                    }
                }
                """
                let data = json.data(using: .utf8)!
                jsonData = try! JSONSerialization.jsonObject(with: data, options: .allowFragments) as! [String: Any]
            }

            context("with supported page index formats") {
                it("parses all formats successfully") {
                    do {
                        let decoded = try SettingsResponse(response: jsonData!)
                        expect(decoded.pageIndices.indices.count).to(equal(4))

                        guard decoded.pageIndices.indices.count == 4 else { return }

                        if let index = decoded.pageIndices.indices.first(where: { $0.key == "ZYI76ILE" }) {
                            expect(index.libraryId).to(equal(.custom(.myLibrary)))
                            expect(index.value).to(equal("1"))
                        } else {
                            fail("Missing page index ZYI76ILE")
                        }

                        if let index = decoded.pageIndices.indices.first(where: { $0.key == "ZYI76ILF" }) {
                            expect(index.libraryId).to(equal(.custom(.myLibrary)))
                            expect(index.value).to(equal("2.2"))
                        } else {
                            fail("Missing page index ZYI76ILE")
                        }

                        if let index = decoded.pageIndices.indices.first(where: { $0.key == "ZYI76ILG" }) {
                            expect(index.libraryId).to(equal(.custom(.myLibrary)))
                            expect(index.value).to(equal("2.233"))
                        } else {
                            fail("Missing page index ZYI76ILE")
                        }

                        if let index = decoded.pageIndices.indices.first(where: { $0.key == "ZYI76ILH" }) {
                            expect(index.libraryId).to(equal(.group(333)))
                            expect(index.value).to(equal("asda"))
                        } else {
                            fail("Missing page index ZYI76ILE")
                        }
                    } catch let error {
                        fail(error.localizedDescription)
                    }
                }
            }
        }
    }
}
