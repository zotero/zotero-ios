//
//  CodableModelSpec.swift
//  ZoteroTests
//
//  Created by Michal Rentka on 08/07/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

@testable import Zotero

import Nimble
import Quick

class CodableModelSpec: QuickSpec {
    private static let apiClient = ZoteroApiClient(baseUrl: ApiConstants.baseUrlString, configuration: URLSessionConfiguration.default)
    private static let fileStorage = FileStorageController()
    private static let schemaController = SchemaController()

    override func spec() {
        it("collection codes & decodes") {
            guard let url = Bundle(for: type(of: self)).url(forResource: "test_collection", withExtension: "json") else {
                fail("Could not find json file")
                return
            }
            let data = try! Data(contentsOf: url)
            let initialCollection = try! JSONDecoder().decode(CollectionResponse.self, from: data)

            expect(initialCollection.key).to(equal("BBBBBBBB"))
            expect(initialCollection.version).to(equal(81))
            expect(initialCollection.library.libraryId).to(equal(.group(1234123)))
            expect(initialCollection.data.name).to(equal("Bachelor sources"))
            expect(initialCollection.data.parentCollection).to(beNil())

            let encodedData = try! JSONEncoder().encode(initialCollection)
            let decodedCollection = try! JSONDecoder().decode(CollectionResponse.self, from: encodedData)

            expect(initialCollection.key).to(equal(decodedCollection.key))
            expect(initialCollection.version).to(equal(decodedCollection.version))
            expect(initialCollection.library.libraryId).to(equal(decodedCollection.library.libraryId))
            expect(initialCollection.data.name).to(equal(decodedCollection.data.name))
            expect(decodedCollection.data.parentCollection).to(beNil())
        }

        it("search codes & decodes") {
            guard let url = Bundle(for: type(of: self)).url(forResource: "test_search", withExtension: "json") else {
                fail("Could not find json file")
                return
            }
            let data = try! Data(contentsOf: url)
            let initialSearch = try! JSONDecoder().decode(SearchResponse.self, from: data)

            expect(initialSearch.key).to(equal("CCCCCCCC"))
            expect(initialSearch.version).to(equal(64))
            expect(initialSearch.library.libraryId).to(equal(.custom(.myLibrary)))
            expect(initialSearch.data.name).to(equal("Journal search"))
            expect(initialSearch.data.conditions.count).to(equal(3))
            expect(initialSearch.data.conditions[0].condition).to(equal("itemType"))
            expect(initialSearch.data.conditions[0].operator).to(equal("is"))
            expect(initialSearch.data.conditions[0].value).to(equal("artwork"))
            expect(initialSearch.data.conditions[2].condition).to(equal("joinMode"))
            expect(initialSearch.data.conditions[2].operator).to(equal("any"))

            let encodedData = try! JSONEncoder().encode(initialSearch)
            let decodedSearch = try! JSONDecoder().decode(SearchResponse.self, from: encodedData)

            expect(initialSearch.key).to(equal(decodedSearch.key))
            expect(initialSearch.version).to(equal(decodedSearch.version))
            expect(initialSearch.library.libraryId).to(equal(decodedSearch.library.libraryId))
            expect(initialSearch.data.name).to(equal(decodedSearch.data.name))
            expect(initialSearch.data.conditions.count).to(equal(decodedSearch.data.conditions.count))
            expect(initialSearch.data.conditions[0].condition).to(equal(decodedSearch.data.conditions[0].condition))
            expect(initialSearch.data.conditions[0].operator).to(equal(decodedSearch.data.conditions[0].operator))
            expect(initialSearch.data.conditions[0].value).to(equal(decodedSearch.data.conditions[0].value))
            expect(initialSearch.data.conditions[2].condition).to(equal(decodedSearch.data.conditions[2].condition))
            expect(initialSearch.data.conditions[2].operator).to(equal(decodedSearch.data.conditions[2].operator))
        }

        it("Item decodes from JSON") {
            guard let url = Bundle(for: type(of: self)).url(forResource: "test_item", withExtension: "json") else {
                fail("Could not find json file")
                return
            }
            let data = try! Data(contentsOf: url)
            guard let json = (try! JSONSerialization.jsonObject(with: data, options: .allowFragments)) as? [String: Any] else {
                fail("Json file is not dictionary")
                return
            }

            let item = try! ItemResponse(response: json, schemaController: CodableModelSpec.schemaController)
            expect(item.rawType).to(equal("thesis"))
            expect(item.version).to(equal(182))
            expect(item.isTrash).to(beFalse())
            expect(item.library.libraryId).to(equal(.custom(.myLibrary)))
            expect(item.collectionKeys).to(equal(["2PDUK4DH"]))
            expect(item.links?.alternate?.href).to(equal("https://www.zotero.org/someuser/items/AAAAAAAA"))
            expect(item.creators.count).to(equal(2))
            expect(item.creators.first?.firstName).to(equal("Some"))
            expect(item.creators.first?.lastName).to(equal("Author"))
            expect(item.tags.count).to(equal(2))
            expect(item.tags.first?.tag).to(equal("High priority"))
            expect(item.fields["url"]).to(equal("https://link.com/thesis"))
            expect(item.fields["abstractNote"]).to(equal("Some note"))
        }
    }
}
