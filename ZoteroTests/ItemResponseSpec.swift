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
    override func spec() {
        it("parses item with all known fields") {
            let url = Bundle(for: type(of: self)).url(forResource: "itemresponse_knownfields", withExtension: "json")!
            let data = try! Data(contentsOf: url)
            let jsonData = try! JSONSerialization.jsonObject(with: data, options: .allowFragments) as! [String: Any]

            do {
                _ = try ItemResponse(response: jsonData, schemaController: TestControllers.schemaController)
            } catch let error {
                fail("Exception thrown during parsing: \(error)")
            }
        }

        it("throws exception for item with unknown field") {
            let url = Bundle(for: type(of: self)).url(forResource: "itemresponse_unknownfields", withExtension: "json")!
            let data = try! Data(contentsOf: url)
            let jsonData = try! JSONSerialization.jsonObject(with: data, options: .allowFragments) as! [String: Any]

            do {
                _ = try ItemResponse(response: jsonData, schemaController: TestControllers.schemaController)
                fail("No exception thrown for unknown fields")
            } catch let error {
                if let error = error as? SchemaError,
                    case .unknownField(_, let fieldName) = error,
                    fieldName == "unknownField" {
                } else {
                    fail("Wrong exception thrown for unknown field: \(error)")
                }
            }
        }
    }
}
