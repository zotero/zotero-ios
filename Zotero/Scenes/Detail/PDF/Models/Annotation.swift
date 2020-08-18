//
//  Annotation.swift
//  Zotero
//
//  Created by Michal Rentka on 29/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

struct Annotation {
    enum Kind: Int {
        case highlight, note, area
    }

    let key: String
    let type: Kind
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

    init(key: String, type: Kind, page: Int, pageLabel: String, rects: [CGRect], author: String, isAuthor: Bool, color: String, comment: String,
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

    init(annotation: RAnnotation) {
        self.key = annotation.key
        self.type = Kind(rawValue: annotation.rawType) ?? .note
        self.page = annotation.page
        self.pageLabel = annotation.pageLabel
        self.rects = annotation.rects.map({ CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) })
        self.author = annotation.author
        self.isAuthor = annotation.isAuthor
        self.color = annotation.color
        self.comment = annotation.comment
        self.text = annotation.text
        self.isLocked = annotation.isLocked
        self.sortIndex = annotation.sortIndex
        self.dateModified = annotation.dateModified
        self.tags = annotation.tags.map({ Tag(tag: $0) })
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
