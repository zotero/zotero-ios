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
    typealias Response = String

    let attachmentKey: String
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> String {
        guard let pageIndex = database.objects(RPageIndex.self).uniqueObject(key: attachmentKey, libraryId: libraryId) else { return "0" }
        return pageIndex.index
    }
}
