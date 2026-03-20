//
//  ReadDocumentAnnotationsCacheDbRequest.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 26/01/26.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadDocumentAnnotationsCacheInfoDbRequest: DbResponseRequest {
    typealias Response = RDocumentAnnotationCacheInfo?

    let attachmentKey: String
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Response {
        return database.objects(RDocumentAnnotationCacheInfo.self)
            .filter(.attachmentKey(attachmentKey, in: libraryId))
            .first
    }
}

struct ReadDocumentAnnotationsDbRequest: DbResponseRequest {
    typealias Response = Results<RDocumentAnnotation>

    let attachmentKey: String
    let libraryId: LibraryIdentifier
    let page: Int?

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Results<RDocumentAnnotation> {
        var annotations = database.objects(RDocumentAnnotation.self)
            .filter(.attachmentKey(attachmentKey, in: libraryId))
        if let page {
            annotations = annotations.filter("page = %d", page)
        }
        annotations = annotations.sorted(byKeyPath: "sortIndex", ascending: true)

        return annotations
    }
}

struct ReadDocumentAnnotationsCacheInfoAndAnnotationsDbRequest: DbResponseRequest {
    typealias Response = (info: RDocumentAnnotationCacheInfo, annotations: Results<RDocumentAnnotation>)?

    let attachmentKey: String
    let libraryId: LibraryIdentifier
    let page: Int?

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Response {
        guard let info = try ReadDocumentAnnotationsCacheInfoDbRequest(attachmentKey: attachmentKey, libraryId: libraryId)
            .process(in: database)
        else { return nil }
        let annotations = try ReadDocumentAnnotationsDbRequest(attachmentKey: attachmentKey, libraryId: libraryId, page: page)
            .process(in: database)

        return (info: info, annotations: annotations)
    }
}

struct ReadDocumentAnnotationKeysDbRequest: DbResponseRequest {
    typealias Response = [PDFReaderAnnotationKey]

    let attachmentKey: String
    let libraryId: LibraryIdentifier
    let page: Int?

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> [PDFReaderAnnotationKey] {
        let annotations = try ReadDocumentAnnotationsDbRequest(attachmentKey: attachmentKey, libraryId: libraryId, page: page)
            .process(in: database)
        return annotations.map({ PDFReaderAnnotationKey(key: $0.key, sortIndex: $0.sortIndex, type: .document) })
    }
}

struct ReadDocumentAnnotationDbRequest: DbResponseRequest {
    typealias Response = RDocumentAnnotation?

    let attachmentKey: String
    let libraryId: LibraryIdentifier
    let key: String

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> RDocumentAnnotation? {
        return database.objects(RDocumentAnnotation.self)
            .filter(.attachmentKey(attachmentKey, in: libraryId))
            .filter(.key(key))
            .first
    }
}
