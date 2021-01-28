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
            item.changedFields = .collections
            item.changeType = .user
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
            self.cleanupAttachmentFiles()
        case ItemTypes.annotation:
            self.cleanupAnnotationFiles()
        default: break
        }
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
        guard let contentType = AttachmentCreator.attachmentContentType(for: self, options: .light, fileStorage: nil, urlDetector: nil) else { return }

        switch contentType {
        case .url: break

        case .snapshot(let htmlFile, _, let zipFile, _):
            // Delete the zip
            NotificationCenter.default.post(name: .attachmentDeleted, object: zipFile)
            // Delete unzipped html directory
            NotificationCenter.default.post(name: .attachmentDeleted, object: htmlFile.directory)

        case .file(let file, _, _, let linkType):
            // Don't try to remove linked attachments
            guard linkType != .linked else { return }

            // Delete attachment file
            NotificationCenter.default.post(name: .attachmentDeleted, object: file)

            guard let libraryId = self.libraryId else { return }

            if file.mimeType == "application/pdf" {
                // This is a PDF file, remove all annotations.
                NotificationCenter.default.post(name: .attachmentDeleted, object: Files.annotationPreviews(for: self.key, libraryId: libraryId))
            }
        }
    }
}

extension RSearch: Deletable {
    func willRemove(in database: Realm) {
        database.delete(self.conditions)
    }
}
