//
//  EditAnnotationRectsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 01.09.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

#if PDFENABLED

import UIKit

import RealmSwift

struct EditAnnotationRectsDbRequest: DbRequest {
    let key: String
    let libraryId: LibraryIdentifier
    let rects: [CGRect]
    unowned let boundingBoxConverter: AnnotationBoundingBoxConverter

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        guard let item = database.objects(RItem.self).filter(.key(self.key, in: self.libraryId)).first else { return }
        let page = UInt(DatabaseAnnotation(item: item).page)
        let dbRects = self.rects.map({ self.boundingBoxConverter.convertToDb(rect: $0, page: page) ?? $0 })
        guard self.rects(dbRects, differFrom: item.rects) else { return }
        self.sync(rects: dbRects, in: item, database: database)
    }

    private func sync(rects: [CGRect], in item: RItem, database: Realm) {
        database.delete(item.rects)

        for rect in rects {
            let rRect = RRect()
            rRect.minX = Double(rect.minX)
            rRect.minY = Double(rect.minY)
            rRect.maxX = Double(rect.maxX)
            rRect.maxY = Double(rect.maxY)
            item.rects.append(rRect)
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

#endif
