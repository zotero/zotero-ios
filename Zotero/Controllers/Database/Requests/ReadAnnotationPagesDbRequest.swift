//
//  ReadAnnotationPagesDbRequest.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 27/01/26.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadAnnotationPagesDbRequest: DbResponseRequest {
    typealias Response = IndexSet

    let attachmentKey: String
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> IndexSet {
        let supportedTypes = AnnotationType.allCases.filter({ AnnotationsConfig.supported.contains($0.kind) }).map({ $0.rawValue })
        let databaseAnnotations = database.objects(RItem.self)
            .filter(.parent(attachmentKey, in: libraryId))
            .filter(.items(type: ItemTypes.annotation, notSyncState: .dirty))
            .filter(.deleted(false))
            .filter("annotationType in %@", supportedTypes)

        var pages = IndexSet()
        for annotation in databaseAnnotations {
            let sortIndex = annotation.annotationSortIndex
            guard let separatorIndex = sortIndex.firstIndex(of: "|"), let page = Int(sortIndex[..<separatorIndex]) else { continue }
            pages.insert(page)
        }
        let cachedDocumentAnnotations = database.objects(RDocumentAnnotation.self)
            .filter(.attachmentKey(attachmentKey, in: libraryId))
        for annotation in cachedDocumentAnnotations {
            pages.insert(annotation.page)
        }

        return pages
    }
}
