//
//  EditNoteDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 07/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct EditNoteDbRequest: DbRequest {
    let note: Note
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return true }

    init(note: Note, libraryId: LibraryIdentifier) {
        self.note = note
        self.libraryId = libraryId
    }

    func process(in database: Realm) throws {
        guard let item = database.objects(RItem.self).filter(.key(self.note.key, in: self.libraryId)).first else {
            throw DbError.objectNotFound
        }

        var changes: RItemChanges = []

        if let field = item.fields.filter(.key(FieldKeys.Item.note)).first, field.value != self.note.text {
            item.set(title: self.note.title)
            item.htmlFreeContent = self.note.text.isEmpty ? nil : self.note.text.strippedHtmlTags
            changes.insert(.fields)

            field.value = self.note.text
            field.changed = true
        }

        self.updateTags(with: self.note.tags, item: item, changes: &changes, database: database)

        if !changes.isEmpty {
            item.changes.append(RObjectChange.create(changes: changes))
            item.changeType = .user
            item.dateModified = Date()
        }
    }

    private func updateTags(with tags: [Tag], item: RItem, changes: inout RItemChanges, database: Realm) {
        let tagsToRemove = item.tags.filter(.tagName(notIn: tags.map({ $0.name })))
        var tagsDidChange = !tagsToRemove.isEmpty

        database.delete(tagsToRemove)

        let allTags = database.objects(RTag.self).filter(.library(with: self.libraryId))

        for tag in tags {
            guard item.tags.filter(.tagName(tag.name)).first == nil else { continue }

            let rTag: RTag

            if let existing = allTags.filter(.name(tag.name)).first {
                rTag = existing
            } else {
                rTag = .create(name: tag.name, color: tag.color, libraryId: libraryId)
                database.add(rTag)
            }

            let rTypedTag = RTypedTag()
            rTypedTag.type = .manual
            database.add(rTypedTag)

            rTypedTag.item = item
            rTypedTag.tag = rTag
            tagsDidChange = true
        }

        if tagsDidChange {
            // TMP: Temporary fix for Realm issue (https://github.com/realm/realm-core/issues/4994). Deletion of tag is not reported, so let's assign a value so that changes are visible in items list.
            item.rawType = item.rawType
            changes.insert(.tags)
        }
    }
}
