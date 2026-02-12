//
//  DeleteDocumentAnnotationsCacheDbRequest.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 26/01/26.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct DeleteDocumentAnnotationsCacheDbRequest: DbRequest {
    let attachmentKey: String
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        for info in database.objects(RDocumentAnnotationCacheInfo.self).filter(.attachmentKey(attachmentKey, in: libraryId)) {
            let linkedAnnotations = info.annotations
            if !linkedAnnotations.isEmpty {
                database.delete(linkedAnnotations)
            }
            database.delete(info)
        }
    }
}
