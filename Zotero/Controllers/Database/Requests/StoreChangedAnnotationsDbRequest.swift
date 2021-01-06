//
//  StoreChangedAnnotationsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 18/08/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import UIKit

import RealmSwift

struct StoreChangedAnnotationsDbRequest: DbRequest {
    var needsWrite: Bool { return true }

    let attachmentKey: String
    let libraryId: LibraryIdentifier
    let annotations: [Annotation]

    unowned let schemaController: SchemaController

    func process(in database: Realm) throws {
        let toRemove = try ReadAnnotationsDbRequest(attachmentKey: self.attachmentKey, libraryId: self.libraryId).process(in: database)
                                                                                                                 .filter(.key(notIn: self.annotations.map({ $0.key })))

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
        self.sync(rects: annotation.rects, in: item, database: database)

        // If position changed add/update embedded_image attachment item
        if annotation.type == .image && item.changedFields.contains(.rects) {
            self.updateImageAttachment(for: annotation, item: item, database: database)
        }

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

        let tagNames = tags.map({ $0.name })
        let tagsToRemove = item.tags.filter(.name(notIn: tagNames))
        tagsToRemove.forEach { tag in
            if let index = tag.items.index(of: item) {
                tag.items.remove(at: index)
            }
            tagsDidChange = true
        }

        tags.forEach { tag in
            let tagsWithName = database.objects(RTag.self).filter(.name(tag.name, in: self.libraryId))

            if tagsWithName.count != 0 {
                if let rTag = tagsWithName.filter("not (any items.key = %@)", item.key).first {
                    rTag.items.append(item)
                    tagsDidChange = true
                }
            } else {
                let rTag = RTag()
                rTag.name = tag.name
                rTag.color = tag.color
                rTag.libraryId = self.libraryId
                database.add(rTag)

                rTag.items.append(item)
                tagsDidChange = true
            }
        }

        if tagsDidChange {
            item.changedFields.insert(.tags)
        }
    }

    private func updateImageAttachment(for annotation: Annotation, item: RItem, database: Realm) {
        // Don't create new attachment item for annotation if it doesn't exist. It's probably just not synced yet and we don't want one
        // annotation to have multiple embeded image attachments.
        guard let attachment = item.children.filter(.items(type: ItemTypes.attachment, notSyncState: .dirty)).first,
              let pdfAttachment = item.parent else { return }

        attachment.dateModified = annotation.dateModified
        attachment.attachmentNeedsSync = true

        if let field = attachment.fields.filter(.key(FieldKeys.Item.Attachment.md5)).first {
            let file = Files.annotationPreview(annotationKey: annotation.key, pdfKey: pdfAttachment.key, isDark: false)
            field.value = md5(from: file.createUrl()) ?? ""
        }
        if let field = attachment.fields.filter(.key(FieldKeys.Item.Attachment.mtime)).first {
            let modificationTime = Int(round(annotation.dateModified.timeIntervalSince1970 * 1000))
            field.value = "\(modificationTime)"
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

        if annotation.type == .image {
            try self.createEmbeddedImageAttachment(for: item, parent: parent, database: database)
        }
        
        return item
    }

    private func createEmbeddedImageAttachment(for item: RItem, parent: RItem, database: Realm) throws {
        let localizedType = self.schemaController.localized(itemType: ItemTypes.attachment) ?? ""
        let file = Files.annotationPreview(annotationKey: item.key, pdfKey: parent.key, isDark: false)
        let attachmentKey = KeyGenerator.newKey
        let attachment = Attachment(key: attachmentKey, title: attachmentKey,
                                    type: .file(file: file, filename: "image.png", location: .local, linkType: .embeddedImage),
                                    libraryId: self.libraryId)
        let attachmentItem = try CreateAttachmentDbRequest(attachment: attachment, localizedType: localizedType,
                                                           collections: []).process(in: database)
        attachmentItem.dateAdded = item.dateAdded
        attachmentItem.dateModified = item.dateAdded
        attachmentItem.parent = item
        attachmentItem.changedFields.insert(.parent)
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
