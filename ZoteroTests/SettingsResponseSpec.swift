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
                            expect(index.value).to(equal("2.2"))
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

        describe("a JSON settings response with read aloud positions") {
            var jsonData: [String: Any]!

            justBeforeEach {
                let json = """
                {
                    "lastReadAloudPosition_u_EB5U2HD8": {
                        "value": {
                            "pageIndex": 69,
                            "rects": [[138, 611, 427.3000000000001, 620.3]]
                        },
                        "version": 27577
                    },
                    "lastReadAloudPosition_u_AHM6G78W": {
                        "value": {
                            "type": "FragmentSelector",
                            "value": "epubcfi(/6/14!/4/2/16/18/6/1,:0,:94)",
                            "conformsTo": "http://www.idpf.org/epub/linking/cfi/epub-cfi.html"
                        },
                        "version": 27586
                    }
                }
                """
                let data = json.data(using: .utf8)!
                jsonData = try! JSONSerialization.jsonObject(with: data, options: .allowFragments) as! [String: Any]
            }

            context("with both document kinds") {
                it("parses page rects and reader source positions") {
                    do {
                        let decoded = try SettingsResponse(response: jsonData!)
                        expect(decoded.lastReadAloudPositions.positions.count).to(equal(2))

                        if let position = decoded.lastReadAloudPositions.positions.first(where: { $0.key == "EB5U2HD8" }) {
                            expect(position.libraryId).to(equal(.custom(.myLibrary)))
                            expect(position.version).to(equal(27577))
                            guard case .pdf(let pageIndex, let rects) = position.value else {
                                fail("Position EB5U2HD8 is not a PDF position")
                                return
                            }
                            expect(pageIndex).to(equal(69))
                            expect(rects.count).to(equal(1))
                            expect(rects.first?.minX).to(beCloseTo(138))
                            expect(rects.first?.minY).to(beCloseTo(611))
                            expect(rects.first?.maxX).to(beCloseTo(427.3))
                            expect(rects.first?.maxY).to(beCloseTo(620.3))
                        } else {
                            fail("Missing read aloud position EB5U2HD8")
                        }

                        if let position = decoded.lastReadAloudPositions.positions.first(where: { $0.key == "AHM6G78W" }) {
                            expect(position.libraryId).to(equal(.custom(.myLibrary)))
                            expect(position.version).to(equal(27586))
                            guard case .reader(let source) = position.value else {
                                fail("Position AHM6G78W is not a reader position")
                                return
                            }
                            expect(source["type"] as? String).to(equal("FragmentSelector"))
                            expect(source["value"] as? String).to(equal("epubcfi(/6/14!/4/2/16/18/6/1,:0,:94)"))
                        } else {
                            fail("Missing read aloud position AHM6G78W")
                        }
                    } catch let error {
                        fail(error.localizedDescription)
                    }
                }
            }
        }
    }
}
