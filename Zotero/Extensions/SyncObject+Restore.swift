//
//  SyncObject+Restore.swift
//  Zotero
//
//  Created by Michal Rentka on 15.02.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

extension RCollection {
    func markAsChanged(in database: Realm) {
        self.changedFields = .name
        self.changeType = .user
        self.deleted = false
        self.version = 0

        if self.parentKey != nil {
            self.changedFields.insert(.parent)
        }

        self.items.forEach { item in
            item.changedFields = .collections
            item.changeType = .user
        }

        if let libraryId = self.libraryId {
            let children = database.objects(RCollection.self).filter(.parentKey(self.key, in: libraryId))
            children.forEach { child in
                child.markAsChanged(in: database)
            }
        }
    }
}

extension RSearch {
    func markAsChanged(in database: Realm) {
        self.changedFields = .all
        self.changeType = .user
        self.deleted = false
        self.version = 0
    }
}

extension RItem {
    func markAsChanged(in database: Realm) {
        self.changedFields = self.currentChanges
        self.changeType = .user
        self.deleted = false
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
