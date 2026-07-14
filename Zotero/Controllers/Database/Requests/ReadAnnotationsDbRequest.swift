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

struct ReadDefaultAnnotationPageLabelDbRequest: DbResponseRequest {
    typealias Response = DefaultAnnotationPageLabel

    let attachmentKey: String
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> DefaultAnnotationPageLabel {
        let supportedTypes = AnnotationType.allCases.filter({ AnnotationsConfig.supported.contains($0.kind) }).map({ $0.rawValue })
        let annotations = database.objects(RItem.self)
            .filter(.parent(attachmentKey, in: libraryId))
            .filter(.items(type: ItemTypes.annotation, notSyncState: .dirty))
            .filter(.deleted(false))
            .filter("annotationType in %@", supportedTypes)

        var uniquePageLabelsCountByPage: [Int: [String: Int]] = [:]
        for item in annotations {
            var rawPage: String?
            var pageLabel: String?
            for field in item.fields {
                switch field.key {
                case FieldKeys.Item.Annotation.Position.pageIndex:
                    rawPage = field.value

                case FieldKeys.Item.Annotation.pageLabel:
                    pageLabel = field.value

                default:
                    continue
                }
                if rawPage != nil && pageLabel != nil {
                    break
                }
            }

            guard let rawPage,
                  let page = Int(rawPage) ?? Double(rawPage).flatMap(Int.init),
                  let pageLabel,
                  !pageLabel.isEmpty,
                  pageLabel != "-"
            else { continue }

            var uniquePageLabelsCount = uniquePageLabelsCountByPage[page, default: [:]]
            uniquePageLabelsCount[pageLabel, default: 0] += 1
            uniquePageLabelsCountByPage[page] = uniquePageLabelsCount
        }

        var defaultPageLabelByPage: [Int: String] = [:]
        for (page, uniquePageLabelsCount) in uniquePageLabelsCountByPage {
            if let maxCount = uniquePageLabelsCount.values.max(),
               let defaultPageLabel = uniquePageLabelsCount.filter({ $0.value == maxCount }).keys.sorted().first {
                defaultPageLabelByPage[page] = defaultPageLabel
            }
        }

        let uniquePageOffsets = Set(defaultPageLabelByPage.map({ (page, pageLabel) in Int(pageLabel).flatMap({ $0 - page }) }))
        if uniquePageOffsets.count == 1, let uniquePageOffset = uniquePageOffsets.first, let commonPageOffset = uniquePageOffset {
            return .commonPageOffset(offset: commonPageOffset)
        }
        if !defaultPageLabelByPage.isEmpty {
            return .labelPerPage(labelsByPage: defaultPageLabelByPage)
        }
        return .commonPageOffset(offset: 1)
    }
}

struct ReadFilteredCombinedAnnotationKeysDbRequest: DbResponseRequest {
    typealias Response = Set<String>

    let attachmentKey: String
    let libraryId: LibraryIdentifier
    let page: Int
    let term: String?
    let filter: AnnotationsFilter
    let displayName: String
    let username: String

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Set<String> {
        var keys = Set<String>()

        let databaseAnnotations = try ReadAnnotationsDbRequest(attachmentKey: attachmentKey, libraryId: libraryId, page: page)
            .process(in: database)
        for item in databaseAnnotations {
            guard let annotation = PDFDatabaseAnnotation(item: item),
                  annotation.matches(term: term, filter: filter, displayName: displayName, username: username)
            else { continue }
            keys.insert(annotation.key)
        }

        let documentAnnotations = try ReadDocumentAnnotationsDbRequest(attachmentKey: attachmentKey, libraryId: libraryId, page: page)
            .process(in: database)
        for cachedAnnotation in documentAnnotations {
            guard let annotation = PDFDocumentAnnotation(annotation: cachedAnnotation, displayName: displayName, username: username),
                  annotation.matches(term: term, filter: filter, displayName: displayName, username: username)
            else { continue }
            keys.insert(annotation.key)
        }

        return keys
    }
}
