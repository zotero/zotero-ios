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
        }
    }
}
