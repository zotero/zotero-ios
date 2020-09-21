//
//  DeletableObject.swift
//  Zotero
//
//  Created by Michal Rentka on 06/05/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

typealias DeletableObject = Deletable&Object

protocol Deletable: class {
    var deleted: Bool { get set }

    func willRemove(in database: Realm)
}

extension RCollection: Deletable {
    func willRemove(in database: Realm) {
        self.items.forEach { item in
            if let index = item.collections.index(of: self) {
                item.changedFields = .collections
                item.collections.remove(at: index)
            }
        }
        self.children.forEach { child in
            child.willRemove(in: database)
        }
        database.delete(self.children)
    }
}

extension RItem: Deletable {
    func willRemove(in database: Realm) {
        self.children.forEach { child in
            child.willRemove(in: database)
        }
        database.delete(self.children)
        database.delete(self.links)
        database.delete(self.relations)
        database.delete(self.creators)
        database.delete(self.rects)

        if let createdByUser = self.createdBy, let lastModifiedByUser = self.lastModifiedBy,
           createdByUser.identifier == lastModifiedByUser.identifier &&
           createdByUser.createdBy.count == 1 &&
           createdByUser.modifiedBy.count == 1 {
            database.delete(createdByUser)
        } else {
            if let user = self.createdBy, user.createdBy.count == 1 && user.modifiedBy.isEmpty {
                database.delete(user)
            }
            if let user = self.lastModifiedBy, user.createdBy.isEmpty && user.modifiedBy.count == 1 {
                database.delete(user)
            }
        }

        // Cleanup leftover files
        switch self.rawType {
        case ItemTypes.attachment:
            if let file = AttachmentCreator.file(for: self, options: .light),
               let darkFile = AttachmentCreator.file(for: self, options: .dark) {
                // Delete attachment file if this attachment contains a file
                NotificationCenter.default.post(name: .attachmentDeleted, object: file)
                if file.name != darkFile.name {
                    NotificationCenter.default.post(name: .attachmentDeleted, object: darkFile)
                }
            }
            // Try deleting annotation container as well, there's no need to check whether this attachment contains annotations or not,
            // `AttachmentFileCleanupController` doesn't report any errors, so in the worst case it just won't find the folder.
            NotificationCenter.default.post(name: .attachmentDeleted, object: Files.annotationContainer(pdfKey: self.key))
        default: break
        }
    }
}

extension RSearch: Deletable {
    func willRemove(in database: Realm) {}
}
