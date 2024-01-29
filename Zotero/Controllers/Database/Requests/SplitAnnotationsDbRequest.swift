//
//  SplitAnnotationsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 10.03.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RealmSwift

struct SplitAnnotationsDbRequest: DbRequest {
    private struct Point: SplittablePathPoint {
        let x: Double
        let y: Double
    }

    let keys: Set<String>
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        let items = database.objects(RItem.self).filter(.keys(self.keys, in: self.libraryId))

        for item in items {
            self.split(item: item, database: database)
            item.willRemove(in: database)
            database.delete(item)
        }
    }

    /// Splits database annotation if it exceedes position limit.
    /// - parameter item: Database annotation to split
    /// - parameter database: Database
    private func split(item: RItem, database: Realm) {
        guard let annotationType = item.fields.filter(.key(FieldKeys.Item.Annotation.type)).first.flatMap({ AnnotationType(rawValue: $0.value) }) else { return }

        switch annotationType {
        case .highlight:
            let rects = item.rects.map({ CGRect(x: $0.minX, y: $0.minY, width: ($0.maxX - $0.minY), height: ($0.maxY - $0.minY)) })
            
            guard let splitRects = AnnotationSplitter.splitRectsIfNeeded(rects: Array(rects)) else { return }

            for split in splitRects {
                self.createCopyWithoutPathsAndRects(of: item, database: database, additionalChange: { new in
                    for rect in split {
                        let rRect = RRect()
                        rRect.minX = rect.minX
                        rRect.minY = rect.minY
                        rRect.maxX = rect.maxX
                        rRect.maxY = rect.maxY
                        new.rects.append(rRect)
                    }
                    new.changes.append(RObjectChange.create(changes: RItemChanges.rects))
                })
            }

        case .ink:
            let paths = self.points(from: item.paths)

            guard let splitPaths = AnnotationSplitter.splitPathsIfNeeded(paths: paths) else { return }

            for split in splitPaths {
                self.createCopyWithoutPathsAndRects(of: item, database: database) { new in
                    for (idx, path) in split.enumerated() {
                        let rPath = RPath()
                        rPath.sortIndex = idx

                        for (idy, coordinate) in path.enumerated() {
                            let rXCoordinate = RPathCoordinate()
                            rXCoordinate.value = coordinate.x
                            rXCoordinate.sortIndex = idy * 2
                            rPath.coordinates.append(rXCoordinate)

                            let rYCoordinate = RPathCoordinate()
                            rYCoordinate.value = coordinate.y
                            rYCoordinate.sortIndex = (idy * 2) + 1
                            rPath.coordinates.append(rYCoordinate)
                        }

                        new.paths.append(rPath)
                    }
                    new.changes.append(RObjectChange.create(changes: RItemChanges.paths))
                }
            }

        default: break
        }
    }

    private func points(from paths: List<RPath>) -> [[Point]] {
        var points: [[Point]] = []

        for path in paths.sorted(byKeyPath: "sortIndex") {
            let sortedCoordinates = path.coordinates.sorted(byKeyPath: "sortIndex")
            var coordinates: [Point] = []

            for idx in 0..<(sortedCoordinates.count / 2) {
                let xCoord = sortedCoordinates[idx * 2]
                let yCoord = sortedCoordinates[(idx * 2) + 1]
                coordinates.append(Point(x: xCoord.value, y: yCoord.value))
            }

            points.append(coordinates)
        }
        return points
    }

    private func createCopyWithoutPathsAndRects(of item: RItem, database: Realm, additionalChange: (RItem) -> Void) {
        let new = RItem()
        new.key = KeyGenerator.newKey
        new.rawType = item.rawType
        new.localizedType = item.localizedType
        new.dateAdded = item.dateAdded
        new.dateModified = item.dateModified
        new.libraryId = item.libraryId
        new.deleted = item.deleted
        new.syncState = .synced
        new.changeType = .syncResponse
        let changes: RItemChanges = [.parent, .fields, .type, .tags]
        new.changes.append(RObjectChange.create(changes: changes))
        database.add(new)

        new.parent = item.parent
        new.createdBy = item.createdBy
        new.lastModifiedBy = item.lastModifiedBy

        for tag in item.tags {
            let newTag = RTypedTag()
            newTag.type = tag.type
            database.add(newTag)

            newTag.item = new
            newTag.tag = tag.tag
        }

        for field in item.fields {
            let newField = RItemField()
            newField.key = field.key
            newField.baseKey = field.baseKey
            newField.value = field.value
            newField.changed = true
            new.fields.append(newField)
        }

        additionalChange(new)
    }
}
