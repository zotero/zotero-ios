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
        let wasMainAttachment = self.parent?.mainAttachment?.key == self.key
        let parent = self.parent

        self.children.forEach { child in
            child.willRemove(in: database)
        }
        database.delete(self.children)
        database.delete(self.links)
        database.delete(self.relations)
        database.delete(self.creators)

        if wasMainAttachment {
            parent?.updateMainAttachment()
        }

        if self.rawType == ItemTypes.attachment, let file = AttachmentCreator.file(for: self) {
            NotificationCenter.default.post(name: .attachmentDeleted, object: file)
        }
    }
}

extension RSearch: Deletable {
    func willRemove(in database: Realm) {}
}
