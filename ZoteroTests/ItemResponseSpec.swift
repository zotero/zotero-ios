//
//  ItemResponseSpec.swift
//  ZoteroTests
//
//  Created by Michal Rentka on 04/09/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

@testable import Zotero

import Nimble
import Quick

final class ItemResponseSpec: QuickSpec {
    override class func spec() {
        describe("a JSON item response") {
            var resourceName: String!
            var jsonData: [String: Any]!
            
            justBeforeEach {
                let url = Bundle(for: Self.self).url(forResource: resourceName, withExtension: "json")!
                let data = try! Data(contentsOf: url)
                jsonData = try! JSONSerialization.jsonObject(with: data, options: .allowFragments) as! [String: Any]
            }
            
            context("with all known fields") {
                beforeEach {
                    resourceName = "itemresponse_knownfields"
                }
                
                it("is parsed succesfully") {
                    expect(try ItemResponse(response: jsonData, schemaController: TestControllers.schemaController)).toNot(throwError())
                }
            }
            
            context("with unknown field") {
                beforeEach {
                    resourceName = "itemresponse_unknownfields"
                }

                it("throws exception") {
                    expect(try ItemResponse(response: jsonData, schemaController: TestControllers.schemaController)).to(throwError { (error: Error) in
                        expect {
                            guard let error = error as? SchemaError,
                                  case .unknownField(_, let fieldName) = error,
                                  fieldName == "unknownField"
                            else {
                                return .failed(reason: "Wrong exception thrown for unknown field: \(error)")
                            }
                            return .succeeded
                        }
                        .to(succeed())
                    })
                }
            }

            context("with unknown basic position fields") {
                beforeEach {
                    resourceName = "test_annotation_basic_position"
                }

                it("preserves fields") {
                    do {
                        let response = try ItemResponse(response: jsonData, schemaController: TestControllers.schemaController)
                        expect(response.fields[KeyBaseKeyPair(key: "type", baseKey: FieldKeys.Item.Annotation.position)]).to(equal("FragmentSelector"))
                        expect(response.fields[KeyBaseKeyPair(key: "conformsTo", baseKey: FieldKeys.Item.Annotation.position)]).to(equal("http://www.idpf.org/epub/linking/cfi/epub-cfi.html"))
                        expect(response.fields[KeyBaseKeyPair(key: "value", baseKey: FieldKeys.Item.Annotation.position)]).to(equal("epubcfi(/6/102!/4/2[chapter-45]/26,/1:0,/3:254)"))
                    } catch let error {
                        fail("\(error)")
                    }
                }
            }

            context("with unknown array position fields") {
                beforeEach {
                    resourceName = "test_annotation_array_position"
                }

                it("preserves fields") {
                    do {
                        let response = try ItemResponse(response: jsonData, schemaController: TestControllers.schemaController)
                        let nextPageRects = response.fields[KeyBaseKeyPair(key: "nextPageRects", baseKey: FieldKeys.Item.Annotation.position)]
                        expect(nextPageRects).to(equal("[[65.955,709.874,293.106,718.217],[54,700.077,269.333,707.904]]"))
                    } catch let error {
                        fail("\(error)")
                    }
                }
            }

            context("with unknown dictionary position fields") {
                beforeEach {
                    resourceName = "test_annotation_dictionary_position"
                }

                it("preserves fields") {
                    do {
                        let response = try ItemResponse(response: jsonData, schemaController: TestControllers.schemaController)

                        guard let rawRefinedBy = response.fields[KeyBaseKeyPair(key: "refinedBy", baseKey: FieldKeys.Item.Annotation.position)] else {
                            fail("refinedBy missing")
                            return
                        }

                        guard let refinedBy = try? JSONSerialization.jsonObject(with: rawRefinedBy.data(using: .utf8)!, options: .allowFragments) as? [String: Any] else {
                            fail("refinedBy invalid json \(rawRefinedBy)")
                            return
                        }

                        expect(refinedBy["type"] as? String).to(equal("TextPositionSelector"))
                        expect(refinedBy["start"] as? Int).to(equal(1536))
                        expect(refinedBy["end"] as? Int).to(equal(1705))
                    } catch let error {
                        fail("\(error)")
                    }
                }
            }
        }
    }
}
