//
//  SplitAnnotationsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 10.03.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift
import RealmSwift

/// Splits annotations which exceed the position size limit. Returns keys of annotations which were split and replaced by their splits.
struct SplitAnnotationsDbRequest: DbResponseRequest {
    typealias Response = Set<String>

    private struct Point: SplittablePathPoint {
        let x: Double
        let y: Double
    }

    let keys: Set<String>
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws -> Set<String> {
        let items = database.objects(RItem.self).filter(.keys(self.keys, in: self.libraryId))
        let context = DeletionContext()
        var splitKeys: Set<String> = []

        for item in items {
            // The original is replaced by its splits. If it can't be split, it's kept, so that it's not lost.
            guard self.split(item: item, database: database) else {
                DDLogError("SplitAnnotationsDbRequest: can't split annotation \(item.key) in \(libraryId)")
                continue
            }
            splitKeys.insert(item.key)
            context.delete(item, in: database)
        }
        context.cleanup(in: database)
        return splitKeys
    }

    /// Splits database annotation if it exceedes position limit.
    /// - parameter item: Database annotation to split
    /// - parameter database: Database
    /// - returns: `true` if the annotation was split, in which case it should be replaced by the created splits.
    private func split(item: RItem, database: Realm) -> Bool {
        guard let annotationType = item.fields.filter(.key(FieldKeys.Item.Annotation.type)).first.flatMap({ AnnotationType(rawValue: $0.value) }) else { return false }

        switch annotationType {
        case .highlight, .underline:
            let rects = Array(item.rects.map({ CGRect(x: $0.minX, y: $0.minY, width: ($0.maxX - $0.minX), height: ($0.maxY - $0.minY)) }))
            let nextPageRects = Array(item.nextPageRects.map({ CGRect(x: $0.minX, y: $0.minY, width: ($0.maxX - $0.minX), height: ($0.maxY - $0.minY)) }))

            guard let splits = self.splitHighlight(rects: rects, nextPageRects: nextPageRects) else { return false }

            for (index, split) in splits.enumerated() {
                self.createCopyWithoutPathsAndRects(of: item, database: database, additionalChange: { new in
                    self.append(rects: split.rects, to: new.rects)
                    self.append(rects: split.nextPageRects, to: new.nextPageRects)
                    if split.isOnNextPage {
                        self.moveToNextPage(item: new, order: index)
                    }
                    new.changes.append(RObjectChange.create(changes: RItemChanges.rects))
                })
            }
            return true

        case .ink:
            let paths = self.points(from: item.paths)

            guard let splitPaths = AnnotationSplitter.splitPathsIfNeeded(paths: paths) else { return false }

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
            return true

        default:
            return false
        }
    }

    private struct HighlightSplit {
        /// Rects on the page of the split.
        let rects: [CGRect]
        /// Rects on the following page, if the split spans a page break.
        let nextPageRects: [CGRect]
        /// `true` if the split lies only on the page following the original annotation's page.
        let isOnNextPage: Bool
    }

    /// Splits rects of a highlight/underline, which may span a page break, so that each split fits the position size limit.
    ///
    /// Rects of each page are split separately, from the top of the page. The last split of the first page and the first split of the next page
    /// stay together as one annotation spanning the page break, if they fit the limit together. Other splits of the next page become annotations
    /// on the next page.
    /// - returns: Splits, or `nil` if the rects fit the limit and don't need to be split.
    private func splitHighlight(rects: [CGRect], nextPageRects: [CGRect]) -> [HighlightSplit]? {
        let limit = AnnotationsConfig.positionSizeLimit
        guard !nextPageRects.isEmpty else {
            return AnnotationSplitter.splitRectsIfNeeded(rects: rects).map({ $0.map({ HighlightSplit(rects: $0, nextPageRects: [], isOnNextPage: false) }) })
        }
        guard AnnotationSplitter.positionSize(of: rects) + AnnotationSplitter.positionSize(of: nextPageRects) > limit else { return nil }

        var firstPageSplits = AnnotationSplitter.splitRectsIfNeeded(rects: rects) ?? [rects]
        var nextPageSplits = AnnotationSplitter.splitRectsIfNeeded(rects: nextPageRects) ?? [nextPageRects]
        var splits: [HighlightSplit] = []

        let lastFirstPageSplit = firstPageSplits.removeLast()
        let firstNextPageSplit = nextPageSplits.removeFirst()
        let spanningSplit: HighlightSplit?
        if AnnotationSplitter.positionSize(of: lastFirstPageSplit) + AnnotationSplitter.positionSize(of: firstNextPageSplit) <= limit {
            spanningSplit = HighlightSplit(rects: lastFirstPageSplit, nextPageRects: firstNextPageSplit, isOnNextPage: false)
        } else {
            firstPageSplits.append(lastFirstPageSplit)
            nextPageSplits.insert(firstNextPageSplit, at: 0)
            spanningSplit = nil
        }

        splits.append(contentsOf: firstPageSplits.map({ HighlightSplit(rects: $0, nextPageRects: [], isOnNextPage: false) }))
        if let spanningSplit {
            splits.append(spanningSplit)
        }
        splits.append(contentsOf: nextPageSplits.map({ HighlightSplit(rects: $0, nextPageRects: [], isOnNextPage: true) }))
        return splits
    }

    private func append(rects: [CGRect], to list: List<RRect>) {
        for rect in rects {
            let rRect = RRect()
            rRect.minX = rect.minX
            rRect.minY = rect.minY
            rRect.maxX = rect.maxX
            rRect.maxY = rect.maxY
            list.append(rRect)
        }
    }

    /// Moves a split copy of an annotation to the page following the original annotation's page, where its rects lie.
    /// - parameter item: Split copy, with fields copied from the original annotation.
    /// - parameter order: Order of the split, used in the sort index so that splits on the next page keep their order.
    private func moveToNextPage(item: RItem, order: Int) {
        guard let pageField = item.fields.filter(.key(FieldKeys.Item.Annotation.Position.pageIndex, andBaseKey: FieldKeys.Item.Annotation.position)).first,
              let page = Int(pageField.value)
        else { return }
        let nextPage = page + 1
        pageField.value = "\(nextPage)"

        // Sort index (page|text offset|y position) can't be computed without the document, the split is placed at the top of the next page,
        // where the annotation continues.
        let sortIndex = String(format: "%05d|%06d|%05d", nextPage, 0, order)
        item.annotationSortIndex = sortIndex
        item.fields.filter(.key(FieldKeys.Item.Annotation.sortIndex)).first?.value = sortIndex

        // Page label can't be read without the document either, it's derived from the original one when it's a number.
        if let labelField = item.fields.filter(.key(FieldKeys.Item.Annotation.pageLabel)).first, let label = Int(labelField.value) {
            labelField.value = "\(label + 1)"
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
        new.annotationType = item.annotationType
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
