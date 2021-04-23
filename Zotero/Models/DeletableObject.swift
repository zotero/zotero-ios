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

protocol Deletable: AnyObject {
    var deleted: Bool { get set }

    func willRemove(in database: Realm)
}

extension RCollection: Deletable {
    func willRemove(in database: Realm) {
//        if !self.items.isInvalidated {
//            for item in self.items {
//                guard !item.isInvalidated else { continue }
//                item.changedFields = .collections
//                item.changeType = .user
//            }
//        }

        if let libraryId = self.libraryId {
            let children = database.objects(RCollection.self).filter(.parentKey(self.key, in: libraryId))
            if !children.isInvalidated {
                for child in children {
                    guard !child.isInvalidated else { continue }
                    child.willRemove(in: database)
                }
                database.delete(children)
            }
        }
    }
}

extension RItem: Deletable {
    func willRemove(in database: Realm) {
        if !self.children.isInvalidated {
            for child in self.children {
                guard !child.isInvalidated else { continue }
                child.willRemove(in: database)
            }
            database.delete(self.children)
        }
        if !self.links.isInvalidated {
            database.delete(self.links)
        }
        if !self.relations.isInvalidated {
            database.delete(self.relations)
        }
        if !self.creators.isInvalidated {
            database.delete(self.creators)
        }
        if !self.rects.isInvalidated {
            database.delete(self.rects)
        }
        if !self.tags.isInvalidated {
            database.delete(self.tags)
        }

        if let createdByUser = self.createdBy, !createdByUser.isInvalidated, let lastModifiedByUser = self.lastModifiedBy, !lastModifiedByUser.isInvalidated,
           createdByUser.identifier == lastModifiedByUser.identifier &&
           createdByUser.createdBy.count == 1 &&
           createdByUser.modifiedBy.count == 1 {
            database.delete(createdByUser)
        } else {
            if let user = self.createdBy, !user.isInvalidated, user.createdBy.count == 1 && user.modifiedBy.isEmpty {
                database.delete(user)
            }
            if let user = self.lastModifiedBy, !user.isInvalidated, user.createdBy.isEmpty && user.modifiedBy.count == 1 {
                database.delete(user)
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
        guard let libraryId = self.libraryId, let pageIndex = database.objects(RPageIndex.self).filter(.key(self.key, in: libraryId)).first else { return }
        database.delete(pageIndex)
    }

    private func cleanupAnnotationFiles() {
        guard let parentKey = self.parent?.key,
              let libraryId = self.libraryId else { return }

        let light = Files.annotationPreview(annotationKey: self.key, pdfKey: parentKey, libraryId: libraryId, isDark: false)
        let dark = Files.annotationPreview(annotationKey: self.key, pdfKey: parentKey, libraryId: libraryId, isDark: true)

        NotificationCenter.default.post(name: .attachmentDeleted, object: light)
        NotificationCenter.default.post(name: .attachmentDeleted, object: dark)
    }

    private func cleanupAttachmentFiles() {
        guard let contentType = AttachmentCreator.attachmentContentType(for: self, options: .light, fileStorage: nil, urlDetector: nil)?.1 else { return }

        switch contentType {
        case .url: break

        case .file(_, let contentType, _, let linkType):
            // Don't try to remove linked attachments
            guard linkType != .linkedFile, let libraryId = self.libraryId else { return }

            // Delete attachment directory
            NotificationCenter.default.post(name: .attachmentDeleted, object: Files.newAttachmentDirectory(in: libraryId, key: self.key))

            if contentType == "application/pdf" {
                // This is a PDF file, remove all annotations.
                NotificationCenter.default.post(name: .attachmentDeleted, object: Files.annotationPreviews(for: self.key, libraryId: libraryId))
            }
        }
    }
}

extension RSearch: Deletable {
    func willRemove(in database: Realm) {
        if !self.conditions.isInvalidated {
            database.delete(self.conditions)
        }
    }
}
