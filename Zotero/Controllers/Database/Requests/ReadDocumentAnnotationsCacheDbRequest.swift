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
    typealias Response = RDocumentAnnotationsCacheInfo?

    let attachmentKey: String
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Response {
        return database.objects(RDocumentAnnotationsCacheInfo.self)
            .filter(.attachmentKey(attachmentKey, in: libraryId))
            .first
    }
}

struct ReadDocumentAnnotationsDbRequest: DbResponseRequest {
    typealias Response = Results<RDocumentAnnotation>?

    let attachmentKey: String
    let libraryId: LibraryIdentifier
    let page: Int?

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Results<RDocumentAnnotation>? {
        guard let info = try ReadDocumentAnnotationsCacheInfoDbRequest(attachmentKey: attachmentKey, libraryId: libraryId)
            .process(in: database)
        else { return nil }

        if let page {
            return info.annotations
                .filter("page = %d", page)
                .sorted(byKeyPath: "sortIndex", ascending: true)
        }
        return info.annotations
            .sorted(byKeyPath: "sortIndex", ascending: true)
    }
}
