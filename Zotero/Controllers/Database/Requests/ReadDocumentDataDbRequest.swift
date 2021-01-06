//
//  ReadDocumentDataDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 06.01.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

typealias DocumentData = (page: Int, needsImport: Bool)

struct ReadDocumentDataDbRequest: DbResponseRequest {
    typealias Response = DocumentData

    let attachmentKey: String
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> DocumentData {
        guard let item = database.objects(RItem.self).filter(.key(self.attachmentKey, in: self.libraryId)).first else { return (0, false) }

        let page = (item.fields.filter(.key(FieldKeys.Item.Attachment.page)).first?.value).flatMap(Int.init) ?? 0
        let needsImport = (item.fields.filter(.key(FieldKeys.Item.Attachment.hasUnimportedAnnotations)).first?.value).flatMap(Bool.init) ?? false

        return (page, needsImport)
    }
}
