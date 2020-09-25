//
//  Annotation.swift
//  Zotero
//
//  Created by Michal Rentka on 29/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjack

struct Annotation {
    let key: String
    let type: AnnotationType
    let page: Int
    let pageLabel: String
    let rects: [CGRect]
    let author: String
    let isAuthor: Bool
    let color: String
    let comment: String
    let text: String?
    let isLocked: Bool
    let sortIndex: String
    let dateModified: Date
    let tags: [Tag]
    let didChange: Bool
    let editableInDocument: Bool

    init(key: String, type: AnnotationType, page: Int, pageLabel: String, rects: [CGRect], author: String, isAuthor: Bool, color: String, comment: String,
         text: String?, isLocked: Bool, sortIndex: String, dateModified: Date, tags: [Tag], didChange: Bool, editableInDocument: Bool) {
        self.key = key
        self.type = type
        self.page = page
        self.pageLabel = pageLabel
        self.rects = rects
        self.author = author
        self.isAuthor = isAuthor
        self.color = color
        self.comment = comment
        self.text = text
        self.isLocked = isLocked
        self.sortIndex = sortIndex
        self.dateModified = dateModified
        self.tags = tags
        self.didChange = didChange
        self.editableInDocument = editableInDocument
    }

    init?(item: RItem, currentUserId: Int) {
        guard let rawType = item.fieldValue(for: FieldKeys.Item.Annotation.type),
              let pageIndex = item.fieldValue(for: FieldKeys.Item.Annotation.pageIndex).flatMap({ Int($0) }),
              let pageLabel = item.fieldValue(for: FieldKeys.Item.Annotation.pageLabel),
              let color = item.fieldValue(for: FieldKeys.Item.Annotation.color) else {
            return nil
        }
        guard let type = AnnotationType(rawValue: rawType) else {
            DDLogError("Annotation: unknown annotation type '\(rawType)'")
            return nil
        }

        let text = item.fields.filter(.key(FieldKeys.Item.Annotation.text)).first?.value

        if type == .highlight && text == nil {
            DDLogError("Annotation: highlight annotation is missing text property")
            return nil
        }

        let comment = item.fieldValue(for: FieldKeys.Item.Annotation.comment) ?? ""

        let isAuthor: Bool
        let author: String
        if item.customLibrary != nil {
            // In "My Library" current user is always author
            isAuthor = true
            author = ""
        } else {
            // In group library compare `createdBy` user to current user
            isAuthor = item.createdBy?.identifier == currentUserId
            // Users can only edit their own annotations
            if isAuthor {
                author = ""
            } else if let name = item.createdBy?.name, !name.isEmpty {
                author = name
            } else if let name = item.createdBy?.username, !name.isEmpty {
                author = name
            } else {
                author = L10n.unknown
            }
        }

        let editable: Bool
        if type != .image {
            editable = true
        } else {
            // Check whether image annotation has synced embedded image attachment item, if not, the annotation can't be moved or resized
            // (can't be edited in document). The user can still update comment or tags.
            let embeddedImage = item.children.filter(.items(type: ItemTypes.attachment, notSyncState: .dirty)).first(where: { item in
                item.fields.filter(.key(FieldKeys.Item.Attachment.linkMode)).first.flatMap({ LinkMode(rawValue: $0.value) }) == .embeddedImage
            })
            editable = embeddedImage != nil
        }

        self.key = item.key
        self.type = type
        self.page = pageIndex
        self.pageLabel = pageLabel
        self.rects = item.rects.map({ CGRect(x: $0.minX, y: $0.minY, width: ($0.maxX - $0.minX), height: ($0.maxY - $0.minY)) })
        self.author = author
        self.isAuthor = isAuthor
        self.color = color
        self.comment = comment
        self.text = text
        self.isLocked = false
        self.sortIndex = item.annotationSortIndex
        self.dateModified = item.dateModified
        self.tags = item.tags.map({ Tag(tag: $0) })
        self.didChange = false
        self.editableInDocument = editable
    }

    var boundingBox: CGRect {
        if self.rects.count == 1, let boundingBox = self.rects.first {
            return boundingBox
        }

        var minX: CGFloat = .infinity
        var minY: CGFloat = .infinity
        var maxX: CGFloat = 0.0
        var maxY: CGFloat = 0.0

        for rect in self.rects {
            if rect.minX < minX {
                minX = rect.minX
            }
            if rect.minY < minY {
                minY = rect.minY
            }
            if rect.maxX > maxX {
                maxX = rect.maxX
            }
            if rect.maxY > maxY {
                maxY = rect.maxY
            }
        }

        return CGRect(x: minX, y: minY, width: (maxX - minX), height: (maxY - minY))
    }

    func copy(rects: [CGRect], sortIndex: String) -> Annotation {
        return Annotation(key: self.key,
                          type: self.type,
                          page: self.page,
                          pageLabel: self.pageLabel,
                          rects: rects,
                          author: self.author,
                          isAuthor: self.isAuthor,
                          color: self.color,
                          comment: self.comment,
                          text: self.text,
                          isLocked: self.isLocked,
                          sortIndex: sortIndex,
                          dateModified: Date(),
                          tags: self.tags,
                          didChange: true,
                          editableInDocument: self.editableInDocument)
    }

    func copy(comment: String) -> Annotation {
        return Annotation(key: self.key,
                          type: self.type,
                          page: self.page,
                          pageLabel: self.pageLabel,
                          rects: self.rects,
                          author: self.author,
                          isAuthor: self.isAuthor,
                          color: self.color,
                          comment: comment,
                          text: self.text,
                          isLocked: self.isLocked,
                          sortIndex: self.sortIndex,
                          dateModified: Date(),
                          tags: self.tags,
                          didChange: true,
                          editableInDocument: self.editableInDocument)
    }

    func copy(tags: [Tag]) -> Annotation {
        return Annotation(key: self.key,
                          type: self.type,
                          page: self.page,
                          pageLabel: self.pageLabel,
                          rects: self.rects,
                          author: self.author,
                          isAuthor: self.isAuthor,
                          color: self.color,
                          comment: self.comment,
                          text: self.text,
                          isLocked: self.isLocked,
                          sortIndex: self.sortIndex,
                          dateModified: Date(),
                          tags: tags,
                          didChange: true,
                          editableInDocument: self.editableInDocument)
    }

    func copy(text: String?) -> Annotation {
        return Annotation(key: self.key,
                          type: self.type,
                          page: self.page,
                          pageLabel: self.pageLabel,
                          rects: self.rects,
                          author: self.author,
                          isAuthor: self.isAuthor,
                          color: self.color,
                          comment: self.comment,
                          text: text,
                          isLocked: self.isLocked,
                          sortIndex: self.sortIndex,
                          dateModified: Date(),
                          tags: self.tags,
                          didChange: true,
                          editableInDocument: self.editableInDocument)
    }
}

extension RItem {
    fileprivate func fieldValue(for key: String) -> String? {
        let value = self.fields.filter(.key(key)).first?.value
        if value == nil {
            DDLogError("Annotation: missing value for `\(key)`")
        }
        return value
    }
}
