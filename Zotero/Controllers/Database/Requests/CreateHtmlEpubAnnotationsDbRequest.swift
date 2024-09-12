//
//  CreateHtmlEpubAnnotationsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 28.09.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct CreateHtmlEpubAnnotationsDbRequest: DbRequest {
    let attachmentKey: String
    let libraryId: LibraryIdentifier
    let annotations: [HtmlEpubAnnotation]
    let userId: Int

    unowned let schemaController: SchemaController

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        guard let parent = database.objects(RItem.self).filter(.key(attachmentKey, in: libraryId)).first else { return }

        for annotation in annotations {
            create(annotation: annotation, parent: parent, in: database)
        }
    }

    private func create(annotation: HtmlEpubAnnotation, parent: RItem, in database: Realm) {
        let item: RItem

        if let _item = database.objects(RItem.self).filter(.key(annotation.key, in: libraryId)).first {
            if !_item.deleted {
                // If item exists and is not deleted locally, we can ignore this request
                return
            }

            // If item exists and was already deleted locally and not yet synced, we re-add the item
            item = _item
            item.deleted = false
        } else {
            // If item didn't exist, create it
            item = RItem()
            item.key = annotation.key
            item.rawType = ItemTypes.annotation
            item.localizedType = schemaController.localized(itemType: ItemTypes.annotation) ?? ""
            item.libraryId = libraryId
            item.dateAdded = annotation.dateCreated
            database.add(item)
        }

        item.annotationType = annotation.type.rawValue
        item.syncState = .synced
        item.changeType = .user
        item.htmlFreeContent = annotation.comment.isEmpty ? nil : annotation.comment.strippedRichTextTags
        item.dateModified = annotation.dateModified
        item.parent = parent

        if annotation.isAuthor {
            item.createdBy = database.object(ofType: RUser.self, forPrimaryKey: userId)
        }

        // We need to submit tags on creation even if they are empty, so we need to mark them as changed
        addFields(for: annotation, to: item, database: database)
        addTags(for: annotation, to: item, database: database)
        let changes: RItemChanges = [.parent, .fields, .type, .tags]
        item.changes.append(RObjectChange.create(changes: changes))
    }

    private func addFields(for annotation: HtmlEpubAnnotation, to item: RItem, database: Realm) {
        for field in FieldKeys.Item.Annotation.allHtmlEpubFields(for: annotation.type) {
            let rField = RItemField()
            rField.key = field.key
            rField.baseKey = field.baseKey
            rField.changed = true

            switch (field.key, field.baseKey) {
            case (FieldKeys.Item.Annotation.type, nil):
                rField.value = annotation.type.rawValue

            case (FieldKeys.Item.Annotation.color, nil):
                rField.value = annotation.color

            case (FieldKeys.Item.Annotation.comment, nil):
                rField.value = annotation.comment
                
            case (FieldKeys.Item.Annotation.pageLabel, nil):
                rField.value = annotation.pageLabel

            case (FieldKeys.Item.Annotation.sortIndex, nil):
                rField.value = annotation.sortIndex
                item.annotationSortIndex = annotation.sortIndex

            case (FieldKeys.Item.Annotation.text, nil):
                rField.value = annotation.text ?? ""

            case (FieldKeys.Item.Annotation.Position.htmlEpubType, FieldKeys.Item.Annotation.position):
                guard let value = annotation.position[FieldKeys.Item.Annotation.Position.htmlEpubType] as? String else { continue }
                rField.value = value

            case (FieldKeys.Item.Annotation.Position.htmlEpubValue, FieldKeys.Item.Annotation.position):
                guard let value = annotation.position[FieldKeys.Item.Annotation.Position.htmlEpubValue] as? String else { continue }
                rField.value = value

            default: break
            }

            item.fields.append(rField)
        }
    }

    private func addTags(for annotation: HtmlEpubAnnotation, to item: RItem, database: Realm) {
        let allTags = database.objects(RTag.self)

        for tag in annotation.tags {
            guard let rTag = allTags.filter(.name(tag.name)).first else { continue }

            let rTypedTag = RTypedTag()
            rTypedTag.type = .manual
            database.add(rTypedTag)

            rTypedTag.item = item
            rTypedTag.tag = rTag
        }
    }
}
