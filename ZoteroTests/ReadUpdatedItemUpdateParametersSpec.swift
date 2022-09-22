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

final class ReadUpdatedItemUpdateParametersSpec: QuickSpec {
    // Retain realm with inMemoryIdentifier so that data are not deleted
    private var realm: Realm!
    
    override func spec() {
        beforeEach {
            // Create new realm with empty data
            let config = Realm.Configuration(inMemoryIdentifier: UUID().uuidString)
            self.realm = try! Realm(configuration: config)
        }

        it("Sorts changed parent and child item properly") {
            let parentKey = KeyGenerator.newKey
            let childKey = KeyGenerator.newKey

            try! self.realm.write {
                let library = RCustomLibrary()
                self.realm.add(library)

                let child = RItem()
                child.key = childKey
                child.changes.append(RObjectChange.create(changes: RItemChanges.fields))
                child.customLibraryKey = .myLibrary
                self.realm.add(child)

                let childField = RItemField()
                childField.key = "field"
                childField.value = "value"
                childField.changed = true
                child.fields.append(childField)

                let parent = RItem()
                parent.key = parentKey
                parent.changes.append(RObjectChange.create(changes: RItemChanges.fields))
                parent.customLibraryKey = .myLibrary
                self.realm.add(parent)

                let parentField = RItemField()
                parentField.key = "field2"
                parentField.value = "value2"
                parentField.changed = true
                parent.fields.append(parentField)

                child.parent = parent
            }

            self.realm.refresh()

            let (response, _) = try! ReadUpdatedItemUpdateParametersDbRequest(libraryId: .custom(.myLibrary)).process(in: self.realm)

            expect(response.parameters.count).to(be(2))
            expect(response.parameters[0]["key"] as? String).to(equal(parentKey))
            expect(response.parameters[1]["key"] as? String).to(equal(childKey))
        }

        it("Sorts 3 levels of items properly") {
            let parentKey = KeyGenerator.newKey
            let childKey = KeyGenerator.newKey
            let middleKey = KeyGenerator.newKey

            try! self.realm.write {
                let library = RCustomLibrary()
                self.realm.add(library)

                let child = RItem()
                child.key = childKey
                child.changes.append(RObjectChange.create(changes: RItemChanges.fields))
                child.customLibraryKey = .myLibrary
                self.realm.add(child)

                let childField = RItemField()
                childField.key = "field"
                childField.value = "value"
                child.fields.append(childField)

                let middle = RItem()
                middle.key = middleKey
                middle.customLibraryKey = .myLibrary
                self.realm.add(middle)

                let parent = RItem()
                parent.key = parentKey
                parent.changes.append(RObjectChange.create(changes: RItemChanges.fields))
                parent.customLibraryKey = .myLibrary
                self.realm.add(parent)

                let parentField = RItemField()
                parentField.key = "field2"
                parentField.value = "value2"
                parent.fields.append(parentField)

                child.parent = middle
                middle.parent = parent
            }

            self.realm.refresh()

            let (response, _) = try! ReadUpdatedItemUpdateParametersDbRequest(libraryId: .custom(.myLibrary)).process(in: self.realm)

            expect(response.parameters.count).to(be(2))
            expect(response.parameters[0]["key"] as? String).to(equal(parentKey))
            expect(response.parameters[1]["key"] as? String).to(equal(childKey))
        }
    }
}
