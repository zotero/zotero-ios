//
//  ReadDocumentDataDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 06.01.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadDocumentDataDbRequest: DbResponseRequest {
    struct Response {
        let page: String
        /// Sentence where read-aloud playback of this document left off, stored here or synced from another device.
        let lastReadAloudPosition: ReadAloudResumePosition?
    }

    let attachmentKey: String
    let libraryId: LibraryIdentifier
    let defaultPageValue: String

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Response {
        var page = defaultPageValue
        if let pageIndex = database.objects(RPageIndex.self).uniqueObject(key: attachmentKey, libraryId: libraryId), !pageIndex.deleted {
            page = pageIndex.index
        }
        let position = database.objects(RLastReadAloudPosition.self).uniqueObject(key: attachmentKey, libraryId: libraryId)
        return Response(page: page, lastReadAloudPosition: position.flatMap({ $0.deleted ? nil : $0.position }))
    }
}

/// Live results for the attachment's stored read-aloud position, so that a position synced from another device can be
/// picked up while the document is open.
struct ReadLastReadAloudPositionDbRequest: DbResponseRequest {
    typealias Response = Results<RLastReadAloudPosition>

    let attachmentKey: String
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Results<RLastReadAloudPosition> {
        return database.objects(RLastReadAloudPosition.self).filter(.key(attachmentKey, in: libraryId))
    }
}
