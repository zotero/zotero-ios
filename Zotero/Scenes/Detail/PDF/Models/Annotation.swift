//
//  Annotation.swift
//  Zotero
//
//  Created by Michal Rentka on 29/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift

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

    init(key: String, type: AnnotationType, page: Int, pageLabel: String, rects: [CGRect], author: String, isAuthor: Bool, color: String, comment: String,
         text: String?, isLocked: Bool, sortIndex: String, dateModified: Date, tags: [Tag], didChange: Bool) {
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
    }

    init?(item: RItem) {
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

        let text = item.fields.filter(.key(FieldKeys.Item.Annotation.comment)).first?.value

        if type == .highlight && text == nil {
            DDLogError("Annotation: highlight annotation is missing text property")
            return nil
        }

        let comment = item.fieldValue(for: FieldKeys.Item.Annotation.comment) ?? ""

        self.key = item.key
        self.type = type
        self.page = pageIndex
        self.pageLabel = pageLabel
        self.rects = item.rects.map({ CGRect(x: $0.minX, y: $0.minY, width: ($0.maxX - $0.minX), height: ($0.maxY - $0.minY)) })
        self.author = ""
        self.isAuthor = false
        self.color = color
        self.comment = comment
        self.text = text
        self.isLocked = false
        self.sortIndex = item.annotationSortIndex
        self.dateModified = item.dateModified
        self.tags = item.tags.map({ Tag(tag: $0) })
        self.didChange = false
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

    func copy(rects: [CGRect]) -> Annotation {
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
                          sortIndex: self.sortIndex,
                          dateModified: Date(),
                          tags: self.tags,
                          didChange: true)
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
                          didChange: true)
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
                          didChange: true)
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
                          didChange: true)
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
