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

    let itemKey: String
    let libraryId: LibraryIdentifier
    let annotations: [Annotation]

    func process(in database: Realm) throws {
        guard let item = database.objects(RItem.self).filter(.key(self.itemKey, in: self.libraryId)).first else { return }

        let toRemove = item.annotations.filter(.key(notIn: self.annotations.map({ $0.key })))
        // TODO: - only mark as to-remove for sync instead of deleting them here
        database.delete(toRemove)

        for annotation in self.annotations {
            guard annotation.didChange else { continue }
            self.sync(annotation: annotation, to: item, database: database)
        }
    }

    private func sync(annotation: Annotation, to item: RItem, database: Realm) {
        let rAnnotation: RAnnotation

        if let existing = item.annotations.filter(.key(annotation.key)).first {
            rAnnotation = existing
        } else {
            rAnnotation = RAnnotation()
            rAnnotation.key = annotation.key
            database.add(rAnnotation)
        }

        rAnnotation.rawType = annotation.type.rawValue
        rAnnotation.author = annotation.author
        rAnnotation.isAuthor = annotation.isAuthor
        rAnnotation.isLocked = annotation.isLocked
        rAnnotation.color = annotation.color
        rAnnotation.comment = annotation.comment
        rAnnotation.dateModified = annotation.dateModified
        rAnnotation.page = annotation.page
        rAnnotation.pageLabel = annotation.pageLabel
        rAnnotation.sortIndex = annotation.sortIndex
        rAnnotation.text = annotation.text
        rAnnotation.item = item

        // TODO: - add changes to annotation

        self.sync(rects: annotation.rects, in: rAnnotation, database: database)
        self.sync(tags: annotation.tags, in: rAnnotation, database: database)
    }

    private func sync(rects: [CGRect], in annotation: RAnnotation, database: Realm) {
        // Check whether there are any changes from local state
        var hasChanges = rects.count != annotation.rects.count
        if !hasChanges {
            for rect in rects {
                let containsLocally = annotation.rects.filter("x == %d and y == %d and width == %d and height == %d",
                                                              rect.minX, rect.minY, rect.width, rect.height).first != nil
                if !containsLocally {
                    hasChanges = true
                    break
                }
            }
        }

        guard hasChanges else { return }

        database.delete(annotation.rects)
        for rect in rects {
            let rRect = self.createRect(from: rect)
            database.add(rRect)
            annotation.rects.append(rRect)
        }

        // TODO: - add change to annotation if rects changed
    }

    private func createRect(from rect: CGRect) -> RRect {
        let rRect = RRect()
        rRect.x = Double(rect.minX)
        rRect.y = Double(rect.minY)
        rRect.width = Double(rect.width)
        rRect.height = Double(rect.height)
        return rRect
    }

    private func sync(tags: [Tag], in annotation: RAnnotation, database: Realm) {
        var tagsDidChange = false

        let tagNames = tags.map({ $0.name })
        let tagsToRemove = annotation.tags.filter(.name(notIn: tagNames))
        tagsToRemove.forEach { tag in
            if let index = tag.annotations.index(of: annotation) {
                tag.annotations.remove(at: index)
            }
            tagsDidChange = true
        }

        tags.forEach { tag in
            if let rTag = database.objects(RTag.self).filter(.name(tag.name, in: self.libraryId))
                                                     .filter("not (any annotations.key = %@)", annotation.key).first {
                rTag.annotations.append(annotation)
                tagsDidChange = true
            }
        }

        // TODO: - add change to annotation if tags changed
    }
}
