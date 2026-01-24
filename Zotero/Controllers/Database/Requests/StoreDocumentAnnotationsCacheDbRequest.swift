//
//  StoreDocumentAnnotationsCacheDbRequest.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 26/01/26.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct StoreDocumentAnnotationsCacheDbRequest: DbRequest {
    let attachmentKey: String
    let libraryId: LibraryIdentifier
    let md5: String
    let pageCount: Int
    let annotations: [PDFDocumentAnnotation]

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        let existingAnnotations = database.objects(RDocumentAnnotation.self)
            .filter(.attachmentKey(attachmentKey, in: libraryId))
        if !existingAnnotations.isEmpty {
            database.delete(existingAnnotations)
        }

        let existingInfo = database.objects(RDocumentAnnotationCacheInfo.self)
            .filter(.attachmentKey(attachmentKey, in: libraryId))
        if !existingInfo.isEmpty {
            database.delete(existingInfo)
        }

        let info = RDocumentAnnotationCacheInfo()
        info.attachmentKey = attachmentKey
        info.libraryId = libraryId
        info.md5 = md5
        info.pageCount = pageCount
        info.annotationCount = annotations.count
        info.updatedAt = Date()
        info.uniqueBaseColors.append(objectsIn: Set(annotations.map({ $0.color })).sorted())
        database.add(info)

        for annotation in annotations {
            let cachedAnnotation = RDocumentAnnotation()
            cachedAnnotation.key = annotation.key
            cachedAnnotation.attachmentKey = attachmentKey
            cachedAnnotation.libraryId = libraryId
            cachedAnnotation.type = annotation.type.rawValue
            cachedAnnotation.page = annotation.page
            cachedAnnotation.pageLabel = annotation.pageLabel
            cachedAnnotation.lineWidth = annotation.lineWidth.map { Double($0) }
            cachedAnnotation.author = annotation.author
            cachedAnnotation.color = annotation.color
            cachedAnnotation.comment = annotation.comment
            cachedAnnotation.text = annotation.text
            cachedAnnotation.fontSize = annotation.fontSize.map { Double($0) }
            cachedAnnotation.rotation = annotation.rotation.map { Int($0) }
            cachedAnnotation.sortIndex = annotation.sortIndex
            cachedAnnotation.dateAdded = annotation.dateAdded
            cachedAnnotation.dateModified = annotation.dateModified
            cachedAnnotation.cacheInfo = info

            for rect in annotation.rects {
                let rRect = RRect()
                rRect.minX = Double(rect.minX)
                rRect.minY = Double(rect.minY)
                rRect.maxX = Double(rect.maxX)
                rRect.maxY = Double(rect.maxY)
                cachedAnnotation.rects.append(rRect)
            }

            for (pathIndex, path) in annotation.paths.enumerated() {
                let rPath = RPath()
                rPath.sortIndex = pathIndex
                for (pointIndex, point) in path.enumerated() {
                    let rXCoordinate = RPathCoordinate()
                    rXCoordinate.value = Double(point.x)
                    rXCoordinate.sortIndex = pointIndex * 2
                    rPath.coordinates.append(rXCoordinate)

                    let rYCoordinate = RPathCoordinate()
                    rYCoordinate.value = Double(point.y)
                    rYCoordinate.sortIndex = (pointIndex * 2) + 1
                    rPath.coordinates.append(rYCoordinate)
                }
                cachedAnnotation.paths.append(rPath)
            }

            database.add(cachedAnnotation)
        }
    }
}
