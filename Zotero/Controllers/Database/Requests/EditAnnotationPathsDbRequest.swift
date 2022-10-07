//
//  EditAnnotationPathsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 01.09.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

#if PDFENABLED

import UIKit

import RealmSwift

struct EditAnnotationPathsDbRequest: DbRequest {
    let key: String
    let libraryId: LibraryIdentifier
    let paths: [[CGPoint]]
    unowned let boundingBoxConverter: AnnotationBoundingBoxConverter

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        guard let item = database.objects(RItem.self).filter(.key(self.key, in: self.libraryId)).first else { return }
        let page = UInt(DatabaseAnnotation(item: item).page)
        let dbPaths = self.paths.map { path in
            return path.map({ self.boundingBoxConverter.convertToDb(point: $0, page: page) ?? $0 })
        }
        guard self.paths(dbPaths, differFrom: item.paths) else { return }
        self.sync(paths: dbPaths, in: item, database: database)
    }

    private func sync(paths: [[CGPoint]], in item: RItem, database: Realm) {
        for path in item.paths {
            database.delete(path.coordinates)
        }
        database.delete(item.paths)

        for (idx, path) in paths.enumerated() {
            let rPath = RPath()
            rPath.sortIndex = idx

            for (idy, point) in path.enumerated() {
                let rXCoordinate = RPathCoordinate()
                rXCoordinate.value = Double(point.x)
                rXCoordinate.sortIndex = idy * 2
                rPath.coordinates.append(rXCoordinate)

                let rYCoordinate = RPathCoordinate()
                rYCoordinate.value = Double(point.y)
                rYCoordinate.sortIndex = (idy * 2) + 1
                rPath.coordinates.append(rYCoordinate)
            }

            item.paths.append(rPath)
        }

        item.changes.append(RObjectChange.create(changes: RItemChanges.paths))
        item.changeType = .user
    }

    private func paths(_ paths: [[CGPoint]], differFrom itemPaths: List<RPath>) -> Bool {
        if paths.count != itemPaths.count {
            return true
        }

        let sortedPaths = itemPaths.sorted(byKeyPath: "sortIndex")

        for idx in 0..<paths.count {
            let path = paths[idx]
            let itemPath = sortedPaths[idx]

            if (path.count * 2) != itemPath.coordinates.count {
                return true
            }

            let sortedCoordinates = itemPath.coordinates.sorted(byKeyPath: "sortIndex")

            for (idy, point) in path.enumerated() {
                if Double(point.x) != sortedCoordinates[idy * 2].value || Double(point.y) != sortedCoordinates[(idy * 2) + 1].value {
                    return true
                }
            }
        }

        return false
    }
}

#endif
