//
//  ReadUpdatedItemUpdateParametersSpec.swift
//  ZoteroTests
//
//  Created by Michal Rentka on 16/09/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

@testable import Zotero

import RealmSwift
import Nimble
import Quick

class ReadUpdatedItemUpdateParametersSpec: QuickSpec {
    private static var realm: Realm!
    
    override func spec() {
        beforeEach {
            // Create new realm with empty data
            let memoryId = UUID().uuidString
            let config = Realm.Configuration(inMemoryIdentifier: memoryId)
            let realm = try! Realm(configuration: config)

            ReadUpdatedItemUpdateParametersSpec.realm = realm
        }

        it("Sorts changed parent and child item properly") {
            let realm = ReadUpdatedItemUpdateParametersSpec.realm!

            let parentKey = KeyGenerator.newKey
            let childKey = KeyGenerator.newKey

            try! realm.write {
                let library = RCustomLibrary()
                realm.add(library)

                let child = RItem()
                child.key = childKey
                child.changedFields = [.fields]
                child.customLibraryKey.value = library.rawType
                realm.add(child)

                let childField = RItemField()
                childField.key = "field"
                childField.value = "value"
                childField.changed = true
                realm.add(childField)
                childField.item = child

                let parent = RItem()
                parent.key = parentKey
                parent.changedFields = [.fields]
                parent.customLibraryKey.value = library.rawType
                realm.add(parent)

                let parentField = RItemField()
                parentField.key = "field2"
                parentField.value = "value2"
                parentField.changed = true
                realm.add(parentField)
                parentField.item = parent

                child.parent = parent
            }

            realm.refresh()

            let (parameters, _) = try! ReadUpdatedItemUpdateParametersDbRequest(libraryId: .custom(.myLibrary)).process(in: realm)

            expect(parameters.count).to(be(2))
            expect(parameters[0]["key"] as? String).to(equal(parentKey))
            expect(parameters[1]["key"] as? String).to(equal(childKey))
        }

        it("Sorts 3 levels of items properly") {
            let realm = ReadUpdatedItemUpdateParametersSpec.realm!

            let parentKey = KeyGenerator.newKey
            let childKey = KeyGenerator.newKey
            let middleKey = KeyGenerator.newKey

            try! realm.write {
                let library = RCustomLibrary()
                realm.add(library)

                let child = RItem()
                child.key = childKey
                child.changedFields = [.fields]
                child.customLibraryKey.value = library.rawType
                realm.add(child)

                let childField = RItemField()
                childField.key = "field"
                childField.value = "value"
                realm.add(childField)
                childField.item = child

                let middle = RItem()
                middle.key = middleKey
                middle.customLibraryKey.value = library.rawType
                realm.add(middle)

                let parent = RItem()
                parent.key = parentKey
                parent.changedFields = [.fields]
                parent.customLibraryKey.value = library.rawType
                realm.add(parent)

                let parentField = RItemField()
                parentField.key = "field2"
                parentField.value = "value2"
                realm.add(parentField)
                parentField.item = parent

                child.parent = middle
                middle.parent = parent
            }

            realm.refresh()

            let (parameters, _) = try! ReadUpdatedItemUpdateParametersDbRequest(libraryId: .custom(.myLibrary)).process(in: realm)

            expect(parameters.count).to(be(2))
            expect(parameters[0]["key"] as? String).to(equal(parentKey))
            expect(parameters[1]["key"] as? String).to(equal(childKey))
        }
    }
}
