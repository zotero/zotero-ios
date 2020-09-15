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

    func process(in database: Realm) throws {
        let toRemove = try ReadAnnotationsDbRequest(attachmentKey: self.attachmentKey, libraryId: self.libraryId)
                                            .process(in: database)
                                            .filter(.key(notIn: self.annotations.map({ $0.key })))

        let deleteRequest = MarkObjectsAsDeletedDbRequest<RItem>(keys: toRemove.map({ $0.key }), libraryId: self.libraryId)
        try deleteRequest.process(in: database)

        guard let parent = database.objects(RItem.self).filter(.key(self.attachmentKey, in: self.libraryId)).first else { return }

        for annotation in self.annotations {
            guard annotation.didChange else { continue }
            self.sync(annotation: annotation, to: parent, database: database)
        }
    }

    private func sync(annotation: Annotation, to parent: RItem, database: Realm) {
        let item: RItem

        if let existing = parent.children.filter(.key(annotation.key)).first {
            item = existing
        } else {
            item = RItem()
            item.key = annotation.key
            item.rawType = ItemTypes.annotation
            item.dateAdded = annotation.dateModified
            item.changedFields = [.parent, .fields, .type]
            database.add(item)

            item.parent = parent

            let annotationType = annotation.type.rawType

            for field in FieldKeys.Item.Annotation.fields(for: annotationType) {
                let rField = RItemField()
                rField.key = field
                if field == FieldKeys.Item.Annotation.type {
                    rField.value = annotationType
                }
                rField.changed = true
                database.add(rField)

                rField.item = item
            }
        }

        item.dateModified = annotation.dateModified

        self.syncFields(annotation: annotation, in: item, database: database)
        self.sync(tags: annotation.tags, in: item, database: database)
        self.sync(rects: annotation.rects, in: item, database: database)
    }

    private func syncFields(annotation: Annotation, in item: RItem, database: Realm) {
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
            }
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
            if let rTag = database.objects(RTag.self).filter(.name(tag.name, in: self.libraryId))
                                                     .filter("not (any items.key = %@)", item.key).first {
                rTag.items.append(item)
                tagsDidChange = true
            }
        }

        if tagsDidChange {
            item.changedFields.insert(.tags)
        }
    }
}
