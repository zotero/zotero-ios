//
//  ReadFilenameDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 25.01.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadFilenameDbRequest: DbResponseRequest {
    typealias Response = String

    let libraryId: LibraryIdentifier
    let key: String

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> String {
        guard let item = database.objects(RItem.self).filter(.key(self.key, in: self.libraryId)).first, item.rawType == ItemTypes.attachment else {
            throw DbError.objectNotFound
        }

        if let field = item.fields.filter(.key(FieldKeys.Item.Attachment.filename)).first {
            return field.value
        }

        if let field = item.fields.filter(.key(FieldKeys.Item.Attachment.title)).first {
            return field.value
        }

        return item.displayTitle
    }
}
