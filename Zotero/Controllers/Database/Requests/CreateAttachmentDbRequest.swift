//
//  CreateAttachmentDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 07/08/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RealmSwift

struct CreateAttachmentDbRequest: DbResponseRequest {
    enum Error: Swift.Error {
        case cantCreateMd5
        case incorrectMd5Value
        case alreadyExists
    }

    typealias Response = RItem

    let attachment: Attachment
    let parentKey: String?
    let localizedType: String
    let includeAccessDate: Bool
    let collections: Set<String>
    let tags: [TagResponse]

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws -> RItem {
        guard database.objects(RItem.self).uniqueObject(key: attachment.key, libraryId: attachment.libraryId) == nil else {
            DDLogError("CreateAttachmentDbRequest: Trying to create attachment that already exists!")
            throw Error.alreadyExists
        }

        // We need to submit tags on creation even if they are empty, so we need to mark them as changed
        var changes: RItemChanges = [.type, .fields, .tags]

        // Basic info

        let item = RItem()
        item.key = self.attachment.key
        item.rawType = ItemTypes.attachment
        item.localizedType = self.localizedType
        item.syncState = .synced
        item.set(title: self.attachment.title)
        item.changeType = .user
        item.attachmentNeedsSync = true
        item.fileDownloaded = true
        item.dateAdded = self.attachment.dateAdded
        item.dateModified = self.attachment.dateAdded
        item.libraryId = self.attachment.libraryId

        switch self.attachment.type {
        case .file(_, _, _, _, let compressed):
            item.fileCompressed = compressed

        case .url: break
        }

        database.add(item)

        // Fields

        let attachmentKeys = FieldKeys.Item.Attachment.fieldKeys

        for fieldKey in attachmentKeys {
            let value: String

            switch fieldKey {
            case FieldKeys.Item.title:
                value = self.attachment.title

            case FieldKeys.Item.Attachment.linkMode:
                switch self.attachment.type {
                case .file(_, _, _, let linkType, _):
                    switch linkType {
                    case .embeddedImage:
                        value = LinkMode.embeddedImage.rawValue

                    case .importedFile:
                        value = LinkMode.importedFile.rawValue

                    case .importedUrl:
                        value = LinkMode.importedUrl.rawValue

                    case .linkedFile:
                        value = LinkMode.linkedFile.rawValue
                    }

                case .url:
                    value = LinkMode.linkedUrl.rawValue
                }

            case FieldKeys.Item.Attachment.contentType:
                switch self.attachment.type {
                case .file(_, let contentType, _, _, _):
                    value = contentType
                case .url: continue
                }

            case FieldKeys.Item.Attachment.md5:
                guard let file = attachment.file else { continue }
                if let md5Value = md5(from: file.createUrl()) {
                    if md5Value == "<null>" {
                        DDLogError("CreateAttachmentDbRequest: incorrect md5 value for attachment \(self.attachment.key)")
                        throw Error.incorrectMd5Value
                    }
                    value = md5Value
                } else {
                    throw Error.cantCreateMd5
                }

            case FieldKeys.Item.Attachment.mtime:
                switch self.attachment.type {
                case .file:
                    let modificationTime = Int(round(Date().timeIntervalSince1970 * 1000))
                    value = "\(modificationTime)"
                case .url: continue
                }

            case FieldKeys.Item.Attachment.filename:
                switch self.attachment.type {
                case .file(let filename, _, _, _, _):
                    value = filename
                    
                case .url: continue
                }

            case FieldKeys.Item.Attachment.url:
                switch self.attachment.type {
                case .url(let url):
                    value = url.absoluteString

                default:
                    guard let url = self.attachment.url else { continue }
                    value = url
                }

            case FieldKeys.Item.Attachment.path:
                guard let file = attachment.file else { continue }
                value = file.createUrl().path

            case FieldKeys.Item.accessDate:
                guard self.includeAccessDate else { continue }
                value = Formatter.iso8601.string(from: self.attachment.dateAdded)
                
            default: continue
            }

            let field = RItemField()
            field.key = fieldKey
            field.baseKey = nil
            field.value = value
            field.changed = true
            item.fields.append(field)
        }

        // Collections

        self.collections.forEach { key in
            let collection: RCollection

            if let existing = database.objects(RCollection.self).uniqueObject(key: key, libraryId: attachment.libraryId) {
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
            changes.insert(.collections)
        }

        // MARK: - Tags

        // MARK: - Parent

        if let key = self.parentKey, let parent = database.objects(RItem.self).uniqueObject(key: key, libraryId: attachment.libraryId) {
            item.parent = parent
            changes.insert(.parent)
        }

        item.changes.append(RObjectChange.create(changes: changes))

        return item
    }
}
