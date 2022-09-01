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

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        guard let item = database.objects(RItem.self).filter(.key(self.key, in: self.libraryId)).first, self.rects(self.rects, differFrom: item.rects) else { return }
        self.sync(rects: self.rects, in: item, database: database)
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

        item.changedFields.insert(.rects)
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
