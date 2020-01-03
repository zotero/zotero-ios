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

    let attachment: Attachment
    let localizedType: String

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws -> RItem {
        let attachmentKeys = FieldKeys.attachmentFieldKeys

        let item = RItem()
        item.key = self.attachment.key
        item.rawType = ItemTypes.attachment
        item.localizedType = self.localizedType
        item.syncState = .synced
        item.setTitle(self.attachment.title)
        // We need to submit tags on creation even if they are empty, so we need to mark them as changed
        item.changedFields = [.type, .fields, .tags]
        item.attachmentNeedsSync = true
        item.dateAdded = Date()
        item.dateModified = Date()

        switch self.attachment.libraryId {
        case .custom(let type):
            let library = database.object(ofType: RCustomLibrary.self, forPrimaryKey: type.rawValue)
            item.customLibrary = library
        case .group(let identifier):
            let group = database.object(ofType: RGroup.self, forPrimaryKey: identifier)
            item.group = group
        }

        database.add(item)

        for fieldKey in attachmentKeys {
            let field = RItemField()
            field.key = fieldKey
            field.baseKey = nil

            switch self.attachment.type {
            case .file(let file, let filename, _):
                switch fieldKey {
                case FieldKeys.title:
                    field.value = self.attachment.title
                case FieldKeys.filename:
                    field.value = filename
                case FieldKeys.contentType:
                    field.value = file.mimeType
                case FieldKeys.linkMode:
                    field.value = "imported_file"
                case FieldKeys.md5:
                    field.value = md5(from: file.createUrl()) ?? ""
                case FieldKeys.mtime:
                    let modificationTime = Int(round(Date().timeIntervalSince1970 * 1000))
                    field.value = "\(modificationTime)"
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
