//
//  ReadAnnotationsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 18/08/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RealmSwift

struct ReadAnnotationsDbRequest: DbResponseRequest {
    typealias Response = Results<RItem>

    let attachmentKey: String
    let libraryId: LibraryIdentifier
    let page: Int?

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Results<RItem> {
        let supportedTypes = AnnotationType.allCases.filter({ AnnotationsConfig.supported.contains($0.kind) }).map({ $0.rawValue })
        var results = database.objects(RItem.self)
            .filter(.parent(attachmentKey, in: libraryId))
            .filter(.items(type: ItemTypes.annotation, notSyncState: .dirty))
            .filter(.deleted(false))
            .filter("annotationType in %@", supportedTypes)
        if let page {
            let prefix = String(format: "%05d|", page)
            results = results.filter("annotationSortIndex BEGINSWITH %@", prefix)
        }
        return results.sorted(byKeyPath: "annotationSortIndex", ascending: true)
    }
}

struct ReadAnnotationKeysDbRequest: DbResponseRequest {
    typealias Response = [PDFReaderAnnotationKey]

    let attachmentKey: String
    let libraryId: LibraryIdentifier
    let page: Int?
    let validate: Bool

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> [PDFReaderAnnotationKey] {
        let items = try ReadAnnotationsDbRequest(attachmentKey: attachmentKey, libraryId: libraryId, page: page)
            .process(in: database)
        var keys: [PDFReaderAnnotationKey] = []
        for item in items {
            if !validate || isValidDatabaseAnnotation(item: item) {
                keys.append(PDFReaderAnnotationKey(key: item.key, sortIndex: item.annotationSortIndex, type: .database))
            }
        }
        return keys

        func isValidDatabaseAnnotation(item: RItem) -> Bool {
            // Annotation type validity is already provided by the ReadAnnotationsDbRequest. We just need a non-nil value.
            guard let type = AnnotationType(rawValue: item.annotationType),
                  let rawPage = item.fields.filter(.key(FieldKeys.Item.Annotation.Position.pageIndex)).first?.value,
                  Int(rawPage) != nil || Double(rawPage).flatMap(Int.init) != nil
            else {
                return false
            }

            switch type {
            case .ink:
                guard !item.paths.isEmpty else {
                    DDLogInfo("ReadAnnotationKeysDbRequest: \(type) annotation \(item.key) missing paths")
                    return false
                }

            case .highlight, .image, .note, .underline:
                guard !item.rects.isEmpty else {
                    DDLogInfo("ReadAnnotationKeysDbRequest: \(type) annotation \(item.key) missing rects")
                    return false
                }

            case .freeText:
                guard !item.rects.isEmpty else {
                    DDLogInfo("ReadAnnotationKeysDbRequest: \(type) annotation \(item.key) missing rects")
                    return false
                }
                if (item.fields.filter(.key(FieldKeys.Item.Annotation.Position.fontSize)).first?.value).flatMap(Double.init).flatMap(CGFloat.init) == nil {
                    // Since free text annotations are created in AnnotationConverter using `setBoundingBox(annotation.boundingBox(boundingBoxConverter: boundingBoxConverter), transformSize: true)`
                    // it's ok even if they are missing `fontSize`, so we just log it and continue validation.
                    DDLogInfo("ReadAnnotationKeysDbRequest: \(type) annotation \(item.key) missing fontSize")
                }
                guard let rotation = item.fields.filter(.key(FieldKeys.Item.Annotation.Position.rotation)).first?.value, Double(rotation) != nil else {
                    DDLogInfo("ReadAnnotationKeysDbRequest: \(type) annotation \(item.key) missing rotation")
                    return false
                }
            }

            // Sort index consists of 3 parts separated by "|":
            // - 1. page index (5 characters)
            // - 2. character offset (6 characters)
            // - 3. y position from top (5 characters)
            let sortIndex = item.annotationSortIndex
            let parts = sortIndex.split(separator: "|")
            guard parts.count == 3, parts[0].count == 5, parts[1].count == 6, parts[2].count == 5 else {
                DDLogInfo("ReadAnnotationKeysDbRequest: invalid sort index (\(sortIndex)) for \(item.key)")
                return false
            }

            return true
        }
    }
}

struct ReadCombinedAnnotationKeysDbRequest: DbResponseRequest {
    typealias Response = [PDFReaderAnnotationKey]

    let attachmentKey: String
    let libraryId: LibraryIdentifier
    let page: Int?

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> [PDFReaderAnnotationKey] {
        let databaseAnnotationKeys = try ReadAnnotationKeysDbRequest(attachmentKey: attachmentKey, libraryId: libraryId, page: page, validate: true)
            .process(in: database)
        let documentAnnotationKeys = try ReadDocumentAnnotationKeysDbRequest(attachmentKey: attachmentKey, libraryId: libraryId, page: page)
            .process(in: database)
        return (databaseAnnotationKeys + documentAnnotationKeys).sorted(by: { $0.sortIndex < $1.sortIndex })
    }
}
