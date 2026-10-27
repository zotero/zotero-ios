//
//  EditAnnotationRectsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 01.09.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RealmSwift

struct EditAnnotationRectsDbRequest: DbRequest {
    let key: String
    let libraryId: LibraryIdentifier
    let rects: [CGRect]
    /// `true` if `rects` are the part of an annotation spanning a page break which is on the next page (`RItem.nextPageRects`).
    let isNextPagePart: Bool
    let boundingBoxConverter: AnnotationBoundingBoxConverter

    var needsWrite: Bool { return true }

    init(key: String, libraryId: LibraryIdentifier, rects: [CGRect], isNextPagePart: Bool = false, boundingBoxConverter: AnnotationBoundingBoxConverter) {
        self.key = key
        self.libraryId = libraryId
        self.rects = rects
        self.isNextPagePart = isNextPagePart
        self.boundingBoxConverter = boundingBoxConverter
    }

    func process(in database: Realm) throws {
        guard let item = database.objects(RItem.self).uniqueObject(key: key, libraryId: libraryId), let annotation = PDFDatabaseAnnotation(item: item) else { return }
        let page = UInt(isNextPagePart ? annotation.page + 1 : annotation.page)
        let itemRects = isNextPagePart ? item.nextPageRects : item.rects
        let dbRects = rects.map({ boundingBoxConverter.convertToDb(rect: $0, page: page) ?? $0 })
        guard rects(dbRects, differFrom: itemRects) else { return }
        sync(rects: dbRects, in: itemRects, item: item, database: database)
    }

    private func sync(rects: [CGRect], in itemRects: List<RRect>, item: RItem, database: Realm) {
        database.delete(itemRects)

        for rect in rects {
            let rRect = RRect()
            rRect.minX = Double(rect.minX)
            rRect.minY = Double(rect.minY)
            rRect.maxX = Double(rect.maxX)
            rRect.maxY = Double(rect.maxY)
            itemRects.append(rRect)
        }

        item.changes.append(RObjectChange.create(changes: RItemChanges.rects))
        item.changeType = .user
    }

    private func rects(_ rects: [CGRect], differFrom itemRects: List<RRect>) -> Bool {
        if rects.count != itemRects.count {
            return true
        }

        for rect in rects {
            // If rect can't be found in item, it must have changed
            if itemRects.filter("minX == %d and minY == %d and maxX == %d and maxY == %d", rect.minX, rect.minY, rect.maxX, rect.maxY).first == nil {
                return true
            }
        }

        return false
    }
}
