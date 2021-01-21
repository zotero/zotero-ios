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
    let collections: Set<String>

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws -> RItem {
        // Basic info

        let item = RItem()
        item.key = self.attachment.key
        item.rawType = ItemTypes.attachment
        item.localizedType = self.localizedType
        item.syncState = .synced
        item.set(title: self.attachment.title)
        // We need to submit tags on creation even if they are empty, so we need to mark them as changed
        item.changedFields = [.type, .fields, .tags]
        item.changeType = .user
        item.attachmentNeedsSync = true
        item.dateAdded = Date()
        item.dateModified = Date()
        item.libraryId = self.attachment.libraryId

        database.add(item)

        // Fields

        var attachmentKeys = FieldKeys.Item.Attachment.fieldKeys
        // PDFs require extra fields for annotation import and page sync
        if case .file(let file, _, _, _) = self.attachment.contentType, file.mimeType == "application/pdf" {
            attachmentKeys.append(FieldKeys.Item.Attachment.page)
        }

        for fieldKey in attachmentKeys {
            let value: String

            switch fieldKey {
            case FieldKeys.Item.title:
                value = self.attachment.title
            case FieldKeys.Item.Attachment.linkMode:
                switch self.attachment.contentType {
                case .file(_, _, _, let linkType):
                    switch linkType {
                    case .embeddedImage:
                        value = LinkMode.embeddedImage.rawValue
                    case .imported:
                        value = LinkMode.importedFile.rawValue
                    case .linked:
                        value = LinkMode.linkedFile.rawValue
                    }
                case .snapshot:
                    value = LinkMode.importedUrl.rawValue
                case .url:
                    value = LinkMode.linkedUrl.rawValue
                }
            case FieldKeys.Item.Attachment.contentType:
                switch self.attachment.contentType {
                case .file(let file, _, _, _),
                     .snapshot(let file, _, _, _):
                    value = file.mimeType
                case .url: continue
                }
            case FieldKeys.Item.Attachment.md5:
                switch self.attachment.contentType {
                case .file(let file, _, _, _),
                     .snapshot(let file, _, _, _):
                    value = md5(from: file.createUrl()) ?? ""
                case .url: continue
                }
            case FieldKeys.Item.Attachment.mtime:
                switch self.attachment.contentType {
                case .file, .snapshot:
                    let modificationTime = Int(round(Date().timeIntervalSince1970 * 1000))
                    value = "\(modificationTime)"
                case .url: continue
                }
            case FieldKeys.Item.Attachment.filename:
                switch self.attachment.contentType {
                case .file(_, let filename, _, _),
                     .snapshot(_, let filename, _, _):
                    value = filename
                case .url: continue
                }
            case FieldKeys.Item.Attachment.url:
                if case .url(let url) = self.attachment.contentType {
                    value = url.absoluteString
                } else {
                    continue
                }
            case FieldKeys.Item.Attachment.path:
                if case .file(let file, _, _, let linkType) = self.attachment.contentType, linkType == .linked {
                    value = file.createUrl().path
                } else {
                    continue
                }
            case FieldKeys.Item.Attachment.page:
                value = "0"
            default: continue
            }

            let field = RItemField()
            field.key = fieldKey
            field.baseKey = nil
            field.value = value
            field.changed = true
            field.item = item
            database.add(field)
        }

        // Collections

        self.collections.forEach { key in
            let collection: RCollection

            if let existing = database.objects(RCollection.self).filter(.key(key, in: self.attachment.libraryId)).first {
                collection = existing
            } else {
                collection = RCollection()
                collection.key = key
                collection.syncState = .dirty
                collection.libraryId = self.attachment.libraryId
                database.add(collection)
            }

            collection.items.append(item)
        }

        if !self.collections.isEmpty {
            item.changedFields.insert(.collections)
        }

        return item
    }
}
