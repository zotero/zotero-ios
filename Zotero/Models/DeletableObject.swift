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

final class DeletionContext {
    private var userIdsToCheck: Set<Int> = []

    func collect(user: RUser?) {
        guard let user, !user.isInvalidated else { return }
        userIdsToCheck.insert(user.identifier)
    }

    func delete<Obj: DeletableObject>(_ object: Obj, in database: Realm) {
        guard !object.isInvalidated else { return }
        object.willRemove(in: database, context: self)
        database.delete(object)
    }

    func delete<Obj: DeletableObject>(_ objects: Results<Obj>, in database: Realm) {
        for object in objects {
            guard !object.isInvalidated else { continue }
            object.willRemove(in: database, context: self)
        }
        database.delete(objects)
    }

    func cleanup(in database: Realm) {
        for identifier in userIdsToCheck {
            guard let user = database.object(ofType: RUser.self, forPrimaryKey: identifier),
                  !user.isInvalidated,
                  user.createdBy.isEmpty,
                  user.modifiedBy.isEmpty else { continue }

            database.delete(user)
        }
    }
}

protocol Deletable: AnyObject {
    var deleted: Bool { get set }

    func willRemove(in database: Realm, context: DeletionContext)
}

extension Realm {
    func delete<Obj: DeletableObject>(deletable object: Obj) {
        let context = DeletionContext()
        context.delete(object, in: self)
        context.cleanup(in: self)
    }

    func delete<Obj: DeletableObject>(deletable objects: Results<Obj>) {
        let context = DeletionContext()
        context.delete(objects, in: self)
        context.cleanup(in: self)
    }
}

extension RCollection: Deletable {
    func willRemove(in database: Realm, context: DeletionContext) {
        guard let libraryId = self.libraryId else { return }
        if !changes.isInvalidated {
            database.delete(changes)
        }
        let children = database.objects(RCollection.self).filter(.parentKey(self.key, in: libraryId))
        if !children.isInvalidated {
            for child in children {
                guard !child.isInvalidated else { continue }
                child.willRemove(in: database, context: context)
            }
            database.delete(children)
        }
    }
}

extension RItem: Deletable {
    func willRemove(in database: Realm, context: DeletionContext) {
        context.collect(user: createdBy)
        context.collect(user: lastModifiedBy)

        if !changes.isInvalidated {
            database.delete(changes)
        }
        if !self.children.isInvalidated {
            for child in self.children {
                guard !child.isInvalidated else { continue }
                child.willRemove(in: database, context: context)
            }
            database.delete(self.children)
        }
        if !self.tags.isInvalidated {
            let baseTagsToRemove = (try? ReadBaseTagsToDeleteDbRequest(fromTags: self.tags).process(in: database)) ?? []
            database.delete(self.tags)
            if !baseTagsToRemove.isEmpty {
                database.delete(database.objects(RTag.self).filter(.name(in: baseTagsToRemove)))
            }
        }

        // Cleanup leftover files
        switch self.rawType {
        case ItemTypes.attachment:
            self.deletePageIndex(in: database)
            self.cleanupAttachmentFiles()

        case ItemTypes.annotation:
            self.cleanupAnnotationFiles()

        default: break
        }
    }

    private func deletePageIndex(in database: Realm) {
        guard let libraryId = self.libraryId, let pageIndex = database.objects(RPageIndex.self).uniqueObject(key: key, libraryId: libraryId) else { return }
        database.delete(pageIndex)
    }

    private func cleanupAnnotationFiles() {
        #if MAINAPP
        guard let parentKey = parent?.key, let libraryId = libraryId else { return }

        let light = Files.annotationPreview(annotationKey: key, pdfKey: parentKey, libraryId: libraryId, appearance: .light)
        let dark = Files.annotationPreview(annotationKey: key, pdfKey: parentKey, libraryId: libraryId, appearance: .dark)
        let sepia = Files.annotationPreview(annotationKey: key, pdfKey: parentKey, libraryId: libraryId, appearance: .sepia)

        NotificationCenter.default.post(name: .attachmentDeleted, object: light)
        NotificationCenter.default.post(name: .attachmentDeleted, object: dark)
        NotificationCenter.default.post(name: .attachmentDeleted, object: sepia)
        #endif
    }

    private func cleanupAttachmentFiles() {
        guard let type = AttachmentCreator.attachmentType(for: self, options: .light, fileStorage: nil, urlDetector: nil) else { return }

        switch type {
        case .url: break

        case .file(_, let contentType, _, let linkType, _):
            // Don't try to remove linked attachments
            guard linkType != .linkedFile, let libraryId = self.libraryId else { return }

            // Delete attachment directory
            NotificationCenter.default.post(name: .attachmentDeleted, object: Files.attachmentDirectory(in: libraryId, key: self.key))

            #if MAINAPP
            if contentType == "application/pdf" {
                // This is a PDF file, remove all annotations and thumbnails.
                NotificationCenter.default.post(name: .attachmentDeleted, object: Files.annotationPreviews(for: self.key, libraryId: libraryId))
            }
            #endif
        }
    }
}

extension RSearch: Deletable {
    func willRemove(in database: Realm, context: DeletionContext) {
        if !changes.isInvalidated {
            database.delete(changes)
        }
    }
}

extension RLastReadDate: Deletable {
    func willRemove(in database: Realm, context: DeletionContext) {
        if !changes.isInvalidated {
            database.delete(changes)
        }
        guard let groupKey, let item = database.objects(RItem.self).filter(.key(key, in: .group(groupKey))).first else { return }
        item.lastRead = nil
        item.updateEffectiveLastRead()
    }
}

extension RPageIndex: Deletable {
    func willRemove(in database: Realm, context: DeletionContext) {
        if !changes.isInvalidated {
            database.delete(changes)
        }
    }
}
