//
//  RenameAttachmentFilenameDbRequest.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 11/3/25.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct RenameAttachmentFilenameDbRequest: DbResponseRequest {
    typealias Response = StoreItemsResponse.FilenameChange?

    let key: String
    let libraryId: LibraryIdentifier
    let filename: String
    let contentType: String
    unowned let schemaController: SchemaController

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws -> StoreItemsResponse.FilenameChange? {
        guard let item = database.objects(RItem.self).uniqueObject(key: key, libraryId: libraryId) else {
            return nil
        }

        let keyPair = KeyBaseKeyPair(key: FieldKeys.Item.Attachment.filename, baseKey: schemaController.baseKey(for: ItemTypes.attachment, field: FieldKeys.Item.Attachment.filename))
        let filter: NSPredicate = keyPair.baseKey.flatMap({ .key(keyPair.key, andBaseKey: $0) }) ?? .key(keyPair.key)

        guard let field = item.fields.filter(filter).first, filename != field.value else { return nil }
        let oldFilename = field.value
        field.value = filename
        field.changed = true

        return .init(key: key, oldName: oldFilename, newName: filename, contentType: contentType)
    }
}
