//
//  MarkObjectsAsChangedByUser.swift
//  Zotero
//
//  Created by Michal Rentka on 11.02.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct MarkObjectsAsChangedByUser: DbRequest {
    let libraryId: LibraryIdentifier
    let collections: [String]
    let items: [String]

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        self.markCollections(with: self.collections, database: database)
        self.markItems(with: self.items, database: database)
    }

    private func markItems(with keys: [String], database: Realm) {
        let objects = database.objects(RItem.self).filter(.keys(keys, in: self.libraryId))
        for object in objects {
            guard !object.isInvalidated else { continue } // If object is invalidated it has already been removed by some parent before
            object.markAsChanged(in: database)
        }
    }

    private func markCollections(with keys: [String], database: Realm) {
        let objects = database.objects(RCollection.self).filter(.keys(keys, in: self.libraryId))
        for object in objects {
            guard !object.isInvalidated else { continue }
            object.markAsChanged(in: database)
        }
    }
}

extension RCollection {
    fileprivate func markAsChanged(in database: Realm) {
        self.changedFields = .name
        self.changeType = .user
        self.version = 0

        if self.parent != nil {
            self.changedFields.insert(.parent)
        }

        self.items.forEach { item in
            item.changedFields = .collections
            item.changeType = .user
        }

        self.children.forEach { child in
            child.markAsChanged(in: database)
        }
    }
}

extension RItem {
    fileprivate func markAsChanged(in database: Realm) {
        self.changedFields = self.currentChanges
        self.changeType = .user
        self.version = 0

        for field in self.fields {
            guard !field.value.isEmpty else { continue }
            field.changed = true
        }

        if self.rawType == ItemTypes.attachment && self.fields.filter(.containsField(key: FieldKeys.Item.Attachment.linkMode)).first?.value == LinkMode.importedFile.rawValue {
            self.attachmentNeedsSync = true
        }

        self.children.forEach { child in
            child.markAsChanged(in: database)
        }
    }

    private var currentChanges: RItemChanges {
        var changes: RItemChanges = [.type, .fields]
        if !self.creators.isEmpty {
            changes.insert(.creators)
        }
        if self.collections.isEmpty {
            changes.insert(.collections)
        }
        if self.parent != nil {
            changes.insert(.parent)
        }
        if !self.tags.isEmpty {
            changes.insert(.tags)
        }
        if self.trash {
            changes.insert(.trash)
        }
        if !self.relations.isEmpty {
            changes.insert(.relations)
        }
        if !self.rects.isEmpty {
            changes.insert(.rects)
        }
        return changes
    }
}
