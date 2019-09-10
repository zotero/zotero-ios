//
//  CreateAttachmentDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 07/08/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct CreateAttachmentDbRequest: DbResponseRequest {
    typealias Response = RItem

    let attachment: ItemDetailStore.StoreState.Attachment

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws -> RItem {
        let attachmentKeys = FieldKeys.attachmentFieldKeys

        let item = RItem()
        item.key = self.attachment.key
        item.rawType = ItemTypes.attachment
        item.syncState = .synced
        item.title = self.attachment.title
        // We need to submit tags on creation even if they are empty, so we need to mark them as changed
        item.changedFields = [.type, .fields, .tags]
        item.attachmentNeedsSync = true
        item.dateAdded = Date()
        item.dateModified = Date()
        database.add(item)

        for fieldKey in attachmentKeys {
            let field = RItemField()
            field.key = fieldKey

            switch self.attachment.type {
            case .file(let file, _):
                switch fieldKey {
                case FieldKeys.title, FieldKeys.filename:
                    field.value = self.attachment.title
                case FieldKeys.contentType:
                    field.value = file.mimeType
                case FieldKeys.linkMode:
                    field.value = "imported_file"
                case FieldKeys.md5:
                    field.value = md5(from: file.createUrl()) ?? ""
                case FieldKeys.mtime:
                    field.value = "0"
                default:
                    continue
                }

            case .url(let url):
                switch fieldKey {
                case FieldKeys.url:
                    field.value = url.absoluteString
                case FieldKeys.linkMode:
                    field.value = "linked_url"
                default:
                    continue
                }
            }

            field.changed = true
            field.item = item
            database.add(field)
        }

        return item
    }
}
