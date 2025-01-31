//
//  EditItemFieldsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 31.08.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

protocol EditItemFieldsBaseRequest {
    var key: String { get }
    var libraryId: LibraryIdentifier { get }
    var fieldValues: [KeyBaseKeyPair: String] { get }
    var dateParser: DateParser { get }

    func processAndReturnResponse(in database: Realm) throws -> Date?
}

extension EditItemFieldsBaseRequest {
    func processAndReturnResponse(in database: Realm) throws -> Date? {
        guard !fieldValues.isEmpty, let item = database.objects(RItem.self).uniqueObject(key: key, libraryId: libraryId) else { return nil }

        var didChange = false

        for data in fieldValues {
            let filter: NSPredicate = data.key.baseKey.flatMap({ .key(data.key.key, andBaseKey: $0) }) ?? .key(data.key.key)

            guard let field = item.fields.filter(filter).first, data.value != field.value else { continue }

            field.value = data.value
            field.changed = true
            didChange = true

            switch (field.key, field.baseKey) {
            case (FieldKeys.Item.note, _):
                item.htmlFreeContent = data.value.isEmpty ? nil : data.value.strippedHtmlTags

            case (FieldKeys.Item.Annotation.comment, _):
                item.htmlFreeContent = data.value.isEmpty ? nil : data.value.strippedRichTextTags

            case (FieldKeys.Item.title, _), (_, FieldKeys.Item.title):
                item.set(title: field.value)

            case (FieldKeys.Item.date, _), (_, FieldKeys.Item.date):
                item.setDateFieldMetadata(field.value, parser: dateParser)

            case (FieldKeys.Item.publisher, _), (_, FieldKeys.Item.publisher):
                item.set(publisher: field.value)

            case (FieldKeys.Item.publicationTitle, _), (_, FieldKeys.Item.publicationTitle):
                item.set(publicationTitle: field.value)

            default:
                break
            }
        }

        if didChange {
            item.changes.append(RObjectChange.create(changes: RItemChanges.fields))
            item.changeType = .user
            item.dateModified = Date()
            return item.dateModified
        }

        return nil
    }
}

struct EditItemFieldsDbRequest: EditItemFieldsBaseRequest, DbRequest {
    let key: String
    let libraryId: LibraryIdentifier
    let fieldValues: [KeyBaseKeyPair: String]
    let dateParser: DateParser

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        _ = try processAndReturnResponse(in: database)
    }
}

struct EditItemFieldsDbResponseRequest: EditItemFieldsBaseRequest, DbResponseRequest {
    typealias Response = Date?

    let key: String
    let libraryId: LibraryIdentifier
    let fieldValues: [KeyBaseKeyPair: String]
    let dateParser: DateParser

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws -> Date? {
        return try processAndReturnResponse(in: database)
    }
}
