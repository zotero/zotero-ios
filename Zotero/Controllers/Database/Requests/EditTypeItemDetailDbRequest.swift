//
//  EditTypeItemDetailDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 12.10.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct EditTypeItemDetailDbRequest: DbRequest {
    let key: String
    let libraryId: LibraryIdentifier
    let type: String
    var fieldIds: [String]
    var fields: [String: ItemDetailState.Field]
    let creatorIds: [String]
    let creators: [String: ItemDetailState.Creator]
    let dateParser: DateParser

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        guard let item = database.objects(RItem.self).filter(.key(key, in: libraryId)).first else { return }

        item.rawType = type

        var changes: RItemChanges = [.type]
        update(fieldIds: fieldIds, fields: fields, item: item, changes: &changes, database: database)
        update(creatorIds: creatorIds, creators: creators, item: item, changes: &changes, database: database)
        item.changes.append(RObjectChange.create(changes: changes))
    }

    private func update(fieldIds: [String], fields: [String: ItemDetailState.Field], item: RItem, changes: inout RItemChanges, database: Realm) {
        // Remove fields which don't exist for this item type
        let toRemove = item.fields.filter(.key(notIn: fieldIds))
        if !toRemove.isEmpty {
            changes.insert(.fields)
        }
        for field in toRemove {
            switch (field.key, field.baseKey) {
            case (FieldKeys.Item.note, _), (FieldKeys.Item.Annotation.comment, _):
                item.htmlFreeContent = nil

            case (FieldKeys.Item.title, _), (_, FieldKeys.Item.title):
                item.set(title: "")

            case (FieldKeys.Item.date, _), (_, FieldKeys.Item.date):
                item.clearDateFieldMedatada()

            case (FieldKeys.Item.publisher, _), (_, FieldKeys.Item.publisher):
                item.set(publisher: nil)

            case (FieldKeys.Item.publicationTitle, _), (_, FieldKeys.Item.publicationTitle):
                item.set(publicationTitle: nil)

            default:
                break
            }
        }
        database.delete(toRemove)

        for fieldId in fieldIds {
            // Existing fields should not change, only new ones can be created
            guard let field = fields[fieldId], item.fields.filter(.key(fieldId)).first == nil else { continue }

            let rField = RItemField()
            rField.key = field.key
            rField.baseKey = field.baseField
            rField.value = field.value
            rField.changed = true
            item.fields.append(rField)
            changes.insert(.fields)

            switch (field.key, field.baseField) {
            case (FieldKeys.Item.title, _), (_, FieldKeys.Item.title):
                item.set(title: field.value)

            case (FieldKeys.Item.date, _), (_, FieldKeys.Item.date):
                item.setDateFieldMetadata(field.value, parser: dateParser)

            case (FieldKeys.Item.publisher, _), (_, FieldKeys.Item.publisher):
                item.set(publisher: field.value)

            case (FieldKeys.Item.publicationTitle, _), (_, FieldKeys.Item.publicationTitle):
                item.set(publicationTitle: field.value)

            default:
                break
            }
        }
    }

    private func update(creatorIds: [String], creators: [String: ItemDetailState.Creator], item: RItem, changes: inout RItemChanges, database: Realm) {
        // Remove creator types which don't exist for this item type
        let toRemove = item.creators.filter("not uuid in %@", creatorIds)
        if !toRemove.isEmpty {
            changes.insert(.creators)
        }
        database.delete(toRemove)

        for creatorId in creatorIds {
            // When changing item type, only thing that can change for creator is it's type
            guard let creator = creators[creatorId], let rCreator = item.creators.filter("uuid == %@", creatorId).first, rCreator.rawType != creator.type else { continue }
            rCreator.rawType = creator.type
            changes.insert(.creators)
        }

        if changes.contains(.creators) {
            item.updateCreatorSummary()
        }
    }
}
