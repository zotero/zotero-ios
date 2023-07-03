//
//  UpdatableObjectSpec.swift
//  ZoteroTests
//
//  Created by Michal Rentka on 29.06.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

@testable import Zotero

import RealmSwift
import Nimble
import Quick

final class UpdatableObjectSpec: QuickSpec {
    override class func spec() {
        describe("an item object") {
            var realm: Realm!

            beforeSuite {
                let config = Realm.Configuration(inMemoryIdentifier: "TestsRealmConfig")
                realm = try! Realm(configuration: config)
            }

            beforeEach {
                try! realm.write {
                    realm.deleteAll()
                }
            }

            context("with json position fields") {
                it("creates upload parameters properly") {
                    let key = "AAAAAAAA"

                    try! realm.write {
                        let item = RItem()
                        item.key = key
                        item.rawType = ItemTypes.annotation
                        item.dateAdded = Date()
                        item.dateModified = item.dateAdded
                        item.annotationSortIndex = "12312|1234|12312"
                        realm.add(item)

                        let changes: RItemChanges = [.type, .fields]
                        item.changes.append(RObjectChange.create(changes: changes))

                        let typeField = RItemField()
                        typeField.key = FieldKeys.Item.Annotation.type
                        typeField.value = "highlight"
                        item.fields.append(typeField)

                        let sortField = RItemField()
                        sortField.key = FieldKeys.Item.Annotation.sortIndex
                        sortField.value = item.annotationSortIndex
                        sortField.changed = true
                        item.fields.append(sortField)

                        let textField = RItemField()
                        textField.key = FieldKeys.Item.Annotation.text
                        textField.value = "Some text"
                        textField.changed = true
                        item.fields.append(textField)

                        let positionTypeField = RItemField()
                        positionTypeField.key = "type"
                        positionTypeField.value = "CssSelector"
                        positionTypeField.baseKey = FieldKeys.Item.Annotation.position
                        positionTypeField.changed = true
                        item.fields.append(positionTypeField)

                        let positionValueField = RItemField()
                        positionValueField.key = "value"
                        positionValueField.value = "#content > div > div:first-child > div:nth-child(3)"
                        positionValueField.baseKey = FieldKeys.Item.Annotation.position
                        item.fields.append(positionValueField)

                        let positionRefinedByField = RItemField()
                        positionRefinedByField.key = "refinedBy"
                        positionRefinedByField.value = "{\"type\": \"TextPositionSelector\",\"start\": 1536, \"end\": 1705}"
                        positionRefinedByField.baseKey = FieldKeys.Item.Annotation.position
                        item.fields.append(positionRefinedByField)
                    }

                    let item = realm.objects(RItem.self).first!

                    guard let parameters = item.updateParameters else {
                        fail("Parameters are nil")
                        return
                    }

                    expect(parameters["key"] as? String).to(equal(key))
                    expect(parameters["itemType"] as? String).to(equal(ItemTypes.annotation))
                    expect(parameters[FieldKeys.Item.Annotation.sortIndex] as? String).to(equal(item.annotationSortIndex))
                    expect(parameters[FieldKeys.Item.Annotation.text] as? String).to(equal("Some text"))

                    guard let rawPosition = parameters["annotationPosition"] as? String,
                          let position = try? JSONSerialization.jsonObject(with: rawPosition.data(using: .utf8)!) as? [String: Any] else {
                        fail("position missing")
                        return
                    }

                    expect(position["type"] as? String).to(equal("CssSelector"))
                    expect(position["value"] as? String).to(equal("#content > div > div:first-child > div:nth-child(3)"))

                    guard let refinedBy = position["refinedBy"] as? [String: Any] else {
                        fail("refinedBy missing")
                        return
                    }

                    expect(refinedBy["type"] as? String).to(equal("TextPositionSelector"))
                    expect(refinedBy["start"] as? Int).to(equal(1536))
                    expect(refinedBy["end"] as? Int).to(equal(1705))
                }
            }
        }
    }
}
