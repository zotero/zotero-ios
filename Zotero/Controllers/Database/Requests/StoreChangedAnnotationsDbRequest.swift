//
//  StoreChangedAnnotationsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 18/08/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

#if PDFENABLED

import Foundation
import UIKit

import RealmSwift

struct StoreChangedAnnotationsDbRequest: DbRequest {
    let attachmentKey: String
    let libraryId: LibraryIdentifier
    let annotations: [Annotation]
    let deletedKeys: Set<String>

    unowned let schemaController: SchemaController
    unowned let boundingBoxConverter: AnnotationBoundingBoxConverter

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws {
        let toRemove = try ReadAnnotationsDbRequest(attachmentKey: self.attachmentKey, libraryId: self.libraryId).process(in: database).filter(.key(in: self.deletedKeys))

        if !toRemove.isEmpty {
            let deleteRequest = MarkObjectsAsDeletedDbRequest<RItem>(keys: toRemove.map({ $0.key }), libraryId: self.libraryId)
            try deleteRequest.process(in: database)
        }

        guard let parent = database.objects(RItem.self).filter(.key(self.attachmentKey, in: self.libraryId)).first else { return }

        for annotation in self.annotations {
            guard annotation.didChange else { continue }
            try self.sync(annotation: annotation, to: parent, database: database)
        }
    }

    private func sync(annotation: Annotation, to parent: RItem, database: Realm) throws {
        let item: RItem

        if let existing = parent.children.filter(.key(annotation.key)).first {
            item = existing
        } else {
            item = try self.createItem(from: annotation, parent: parent, database: database)
        }

        item.dateModified = annotation.dateModified

        self.syncFields(annotation: annotation, in: item, database: database)
        self.sync(tags: annotation.tags, in: item, database: database)
        self.sync(rects: annotation.rects.compactMap({ self.boundingBoxConverter.convertToDb(rect: $0, page: UInt(annotation.page)) }), in: item, database: database)

        if !item.changedFields.isEmpty {
            item.changeType = .user
        }
    }

    private func syncFields(annotation: Annotation, in item: RItem, database: Realm) {
        var fieldsDidChange = false

        for field in item.fields {
            let newValue: String
            switch field.key {
            case FieldKeys.Item.Annotation.color:
                newValue = annotation.color
            case FieldKeys.Item.Annotation.comment:
                newValue = annotation.comment
            case FieldKeys.Item.Annotation.pageIndex:
                newValue = "\(annotation.page)"
            case FieldKeys.Item.Annotation.pageLabel:
                newValue = annotation.pageLabel
            case FieldKeys.Item.Annotation.sortIndex:
                newValue = annotation.sortIndex
                item.annotationSortIndex = annotation.sortIndex
            case FieldKeys.Item.Annotation.text:
                newValue = annotation.text ?? ""
            default: continue
            }

            let didChange = field.value != newValue
            if didChange {
                field.changed = didChange
                field.value = newValue
                fieldsDidChange = true
            }
        }

        if fieldsDidChange {
            item.changedFields.insert(.fields)
        }
    }

    private func sync(rects: [CGRect], in item: RItem, database: Realm) {
        // Check whether there are any changes from local state
        var hasChanges = rects.count != item.rects.count
        if !hasChanges {
            for rect in rects {
                let containsLocally = item.rects.filter("minX == %d and minY == %d and maxX == %d and maxY == %d",
                                                        rect.minX, rect.minY, rect.maxX, rect.maxY).first != nil
                if !containsLocally {
                    hasChanges = true
                    break
                }
            }
        }

        guard hasChanges else { return }

        database.delete(item.rects)
        for rect in rects {
            let rRect = self.createRect(from: rect)
            database.add(rRect)
            item.rects.append(rRect)
        }

        item.changedFields.insert(.rects)
    }

    private func createRect(from rect: CGRect) -> RRect {
        let rRect = RRect()
        rRect.minX = Double(rect.minX)
        rRect.minY = Double(rect.minY)
        rRect.maxX = Double(rect.maxX)
        rRect.maxY = Double(rect.maxY)
        return rRect
    }

    private func sync(tags: [Tag], in item: RItem, database: Realm) {
        var tagsDidChange = false

        let tagsToRemove = item.tags.filter(.tagName(notIn: tags.map({ $0.name })))
        if !tagsToRemove.isEmpty {
            tagsDidChange = true
        }
        database.delete(tagsToRemove)

        let allTags = database.objects(RTag.self)

        for tag in tags {
            guard item.tags.filter(.tagName(tag.name)).first == nil else { continue }

            let rTag: RTag

            if let existing = allTags.filter(.name(tag.name, in: self.libraryId)).first {
                rTag = existing
            } else {
                rTag = RTag()
                rTag.name = tag.name
                rTag.color = tag.color
                rTag.libraryId = self.libraryId
                database.add(rTag)
            }

            let rTypedTag = RTypedTag()
            rTypedTag.type = .manual
            database.add(rTypedTag)

            rTypedTag.item = item
            rTypedTag.tag = rTag
            tagsDidChange = true
        }

        if tagsDidChange {
            item.changedFields.insert(.tags)
        }
    }

    private func createItem(from annotation: Annotation, parent: RItem, database: Realm) throws -> RItem {
        let item = RItem()
        item.key = annotation.key
        item.rawType = ItemTypes.annotation
        item.localizedType = self.schemaController.localized(itemType: ItemTypes.annotation) ?? ""
        item.syncState = .synced
        // We need to submit tags on creation even if they are empty, so we need to mark them as changed
        item.changedFields = [.parent, .fields, .type, .tags]
        item.dateAdded = annotation.dateModified
        item.libraryId = self.libraryId
        database.add(item)

        item.parent = parent

        self.createMandatoryFields(for: item, annotationType: annotation.type, database: database)
        
        return item
    }

    private func createMandatoryFields(for item: RItem, annotationType: AnnotationType, database: Realm) {
        for field in FieldKeys.Item.Annotation.fields(for: annotationType) {
            let rField = RItemField()
            rField.key = field
            if field == FieldKeys.Item.Annotation.type {
                rField.value = annotationType.rawValue
            }
            rField.changed = true
            database.add(rField)

            rField.item = item
        }
    }
}

#endif
