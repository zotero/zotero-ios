//
//  Annotation.swift
//  Zotero
//
//  Created by Michal Rentka on 29/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift

struct Annotation: Identifiable, Equatable {
    enum Editability: Equatable, Hashable {
        case notEditable
        case metadataEditable
        case editable
    }

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
    let sortIndex: String
    let dateModified: Date
    let tags: [Tag]
    let didChange: Bool
    let editability: Editability
    let isSyncable: Bool

    var id: String {
        return self.key
    }

    var previewBoundingBox: CGRect {
        return self.boundingBox.insetBy(dx: (AnnotationsConfig.imageAnnotationLineWidth + 1), dy: (AnnotationsConfig.imageAnnotationLineWidth + 1))
    }

    init(key: String, type: AnnotationType, page: Int, pageLabel: String, rects: [CGRect], author: String, isAuthor: Bool, color: String, comment: String,
         text: String?, sortIndex: String, dateModified: Date, tags: [Tag], didChange: Bool, editability: Editability, isSyncable: Bool) {
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
        self.sortIndex = sortIndex
        self.dateModified = dateModified
        self.tags = tags
        self.didChange = didChange
        self.editability = editability
        self.isSyncable = isSyncable
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
                          sortIndex: sortIndex,
                          dateModified: Date(),
                          tags: self.tags,
                          didChange: true,
                          editability: self.editability,
                          isSyncable: self.isSyncable)
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
                          sortIndex: self.sortIndex,
                          dateModified: Date(),
                          tags: self.tags,
                          didChange: true,
                          editability: self.editability,
                          isSyncable: self.isSyncable)
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
                          sortIndex: self.sortIndex,
                          dateModified: Date(),
                          tags: tags,
                          didChange: true,
                          editability: self.editability,
                          isSyncable: self.isSyncable)
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
                          sortIndex: self.sortIndex,
                          dateModified: Date(),
                          tags: self.tags,
                          didChange: true,
                          editability: self.editability,
                          isSyncable: self.isSyncable)
    }

    func copy(color: String) -> Annotation {
        return Annotation(key: self.key,
                          type: self.type,
                          page: self.page,
                          pageLabel: self.pageLabel,
                          rects: self.rects,
                          author: self.author,
                          isAuthor: self.isAuthor,
                          color: color,
                          comment: self.comment,
                          text: self.text,
                          sortIndex: self.sortIndex,
                          dateModified: Date(),
                          tags: self.tags,
                          didChange: true,
                          editability: self.editability,
                          isSyncable: self.isSyncable)
    }

    func copy(pageLabel: String) -> Annotation {
        return Annotation(key: self.key,
                          type: self.type,
                          page: self.page,
                          pageLabel: pageLabel,
                          rects: self.rects,
                          author: self.author,
                          isAuthor: self.isAuthor,
                          color: self.color,
                          comment: self.comment,
                          text: self.text,
                          sortIndex: self.sortIndex,
                          dateModified: Date(),
                          tags: self.tags,
                          didChange: true,
                          editability: self.editability,
                          isSyncable: self.isSyncable)
    }

    func copy(didChange: Bool) -> Annotation {
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
                          sortIndex: self.sortIndex,
                          dateModified: self.dateModified,
                          tags: self.tags,
                          didChange: false,
                          editability: self.editability,
                          isSyncable: self.isSyncable)
    }
}

extension Annotation: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(self.key)
        hasher.combine(self.type)
        hasher.combine(self.page)
        hasher.combine(self.pageLabel)
        hasher.combine(self.author)
        hasher.combine(self.isAuthor)
        hasher.combine(self.color)
        hasher.combine(self.comment)
        hasher.combine(self.text)
        hasher.combine(self.sortIndex)
        hasher.combine(self.tags)
        hasher.combine(self.editability)
    }
}
