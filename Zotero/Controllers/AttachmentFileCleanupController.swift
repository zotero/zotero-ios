//
//  AttachmentFileCleanupController.swift
//  Zotero
//
//  Created by Michal Rentka on 12/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxSwift

/// This controller listens to notification center for .attachmentDeleted notification and removes attachment files if needed.
final class AttachmentFileCleanupController {
    enum DeletionType {
        case individual(attachment: Attachment, parentKey: String?)
        case allForItems(Set<String>, LibraryIdentifier)
        case library(LibraryIdentifier)
        case all

        var notification: AttachmentFileDeletedNotification {
            switch self {
            case .all:
                return .all

            case .library(let id):
                return .library(id)

            case .allForItems(let keys, let libraryId):
                return .allForItems(keys: keys, libraryId: libraryId)

            case .individual(let attachment, let parentKey):
                return .individual(key: attachment.key, parentKey: parentKey, libraryId: attachment.libraryId)
            }
        }
    }

    private unowned let fileStorage: FileStorage
    private unowned let dbStorage: DbStorage
    private let queue: DispatchQueue
    private let scheduler: SerialDispatchQueueScheduler
    private let disposeBag: DisposeBag

    init(fileStorage: FileStorage, dbStorage: DbStorage) {
        self.fileStorage = fileStorage
        self.dbStorage = dbStorage
        queue = DispatchQueue(label: "org.zotero.FileCleanupQueue", qos: .userInitiated)
        scheduler = SerialDispatchQueueScheduler(queue: queue, internalSerialQueueName: "org.zotero.FileCleanupScheduler")
        disposeBag = DisposeBag()

        NotificationCenter.default.rx
            .notification(.attachmentDeleted)
            .observe(on: scheduler)
            .subscribe(onNext: { [weak fileStorage] notification in
                guard let fileStorage, let file = notification.object as? File else { return }
                // Don't need to check for errors, the attachment doesn't have to have the file downloaded locally, so this will throw for all attachments
                // without local files. If the file was not removed properly it can always be seen and done in settings.
                try? fileStorage.remove(file)
            })
            .disposed(by: disposeBag)
    }

    /// Delete attachments based on deletion type.
    /// - parameter type: Indicates which attachments should be deleted.
    /// - completed: Called on main queue when attachments are deleted. `true` if attachments were deleted, `false` in case of error.
    func delete(_ type: DeletionType, completed: ((Bool) -> Void)? = nil) {
        queue.async { [weak self] in
            let newTypes = self?.delete(type) ?? []
            DispatchQueue.main.async {
                for type in newTypes {
                    NotificationCenter.default.post(name: .attachmentFileDeleted, object: type.notification)
                }
                completed?(!newTypes.isEmpty)
            }
        }
    }

    /// Deletes attachments based on deletion type.
    /// - parameter type: Indicates which attachments should be deleted.
    /// - returns: An array of deletion types, if all items couldn't be deleted. For example: `.all` would be split into `.allForItems` for libraries, if some items were queued for upload.
    private func delete(_ type: DeletionType) -> [DeletionType] {
        switch type {
        case .all:
            return deleteAll()

        case .allForItems(let keys, let libraryId):
            return deleteAttachments(for: keys, libraryId: libraryId).flatMap({ [$0] }) ?? []

        case .library(let libraryId):
            return delete(in: libraryId).flatMap({ [$0] }) ?? []

        case .individual(let attachment, _):
            return delete(attachment: attachment) ? [type] : []
        }

        /// Tries deleting all attachments.
        /// - returns: Either `.all` deletion type if all attachments can be deleted. If only some can be deleted, it returns `.allForItems` for individual libraries. 
        /// In case of error empty array is returned.
        func deleteAll() -> [DeletionType] {
            do {
                var libraryIds: [LibraryIdentifier] = []
                var forUpload: [LibraryIdentifier: [String]] = [:]

                try dbStorage.perform(on: queue, with: { coordinator in
                    let groups = try coordinator.perform(request: ReadAllGroupsDbRequest())
                    libraryIds = [.custom(.myLibrary)] + groups.map({ .group($0.identifier) })

                    for item in try coordinator.perform(request: ReadAllItemsForUploadDbRequest()) {
                        guard let libraryId = item.libraryId else { continue }

                        var keys = forUpload[libraryId, default: []]
                        keys.append(item.key)
                        forUpload[libraryId] = keys
                    }

                    // TODO: - exclude those for upload
                    try? coordinator.perform(request: MarkAllFilesAsNotDownloadedDbRequest())

                    coordinator.invalidate()
                })

                let deletedIndividually = delete(downloadsIn: libraryIds, forUpload: forUpload)
                // Annotations are not guaranteed to exist and they can be removed even if the parent PDF was not deleted due to upload state.
                // These are generated on device, so they'll just be recreated.
                try? fileStorage.remove(Files.annotationPreviews)
                // Remove page thumbnails
                try? fileStorage.remove(Files.pageThumbnails)
                // When removing all local files clear cache as well.
                try? fileStorage.remove(Files.cache)

                if deletedIndividually.isEmpty {
                    return [.all]
                }

                return deletedIndividually.map { libraryId, keys in
                    return .allForItems(keys, libraryId)
                }
            } catch let error {
                DDLogError("AttachmentFileCleanupController: can't remove download directory - \(error)")
                return []
            }
        }

        /// Tries deleting individual files from given library.
        /// - parameter keys: Individual keys of files to delete.
        /// - parameter libraryId: Library identifier from which files are deleted.
        /// - returns: `nil` if no files could be deleted. `.allForItems` for actually deleted files.
        func deleteAttachments(for keys: Set<String>, libraryId: LibraryIdentifier) -> DeletionType? {
            guard !keys.isEmpty else { return nil }

            do {
                var toDelete: Set<String> = []
                var toReport: Set<String> = []

                try dbStorage.perform(on: queue, with: { coordinator in
                    let items = try coordinator.perform(request: ReadItemsWithKeysDbRequest(keys: keys, libraryId: libraryId))

                    for item in items {
                        // Either the selected item was attachment
                        if item.rawType == ItemTypes.attachment {
                            // Don't delete attachments that need to sync
                            guard !item.attachmentNeedsSync else { continue }
                            toDelete.insert(item.key)
                            toReport.insert(item.key)
                            continue
                        }

                        // Or the item was a parent item and it may have multiple attachments
                        for child in item.children.filter(.item(type: ItemTypes.attachment)) {
                            // Don't delete attachments that need to sync
                            guard !child.attachmentNeedsSync else { continue }
                            // Always report parent key so that the originally requested key gets a report about deletion, even if a child was deleted.
                            toReport.insert(item.key)
                            toDelete.insert(child.key)
                        }
                    }

                    try? coordinator.perform(request: MarkItemsFilesAsNotDownloadedDbRequest(keys: toDelete, libraryId: libraryId))

                    coordinator.invalidate()
                })

                for key in toDelete {
                    // Some files might not exist, just continue deleting
                    try? removeFiles(for: key, libraryId: libraryId)
                }

                return toReport.isEmpty ? nil : .allForItems(toReport, libraryId)
            } catch let error {
                DDLogError("AttachmentFileCleanupController: can't remove attachments for item - \(error)")
                return nil
            }
        }

        /// Tries deleting all attachments in given library.
        /// - returns: Either `.library` deletion type if all attachments can be deleted. If only some can be deleted, it returns `.allForItems` for given library. In case of error `nil` is returned.
        func delete(in libraryId: LibraryIdentifier) -> DeletionType? {
            do {
                var forUpload: [String] = []

                try dbStorage.perform(on: self.queue, with: { coordinator in
                    let items = try coordinator.perform(request: ReadItemsForUploadDbRequest(libraryId: libraryId))
                    forUpload = Array(items.map({ $0.key }))

                    // TODO: - exclude those for upload
                    try? coordinator.perform(request: MarkLibraryFilesAsNotDownloadedDbRequest(libraryId: libraryId))

                    coordinator.invalidate()
                })

                let deletedIndividually = delete(downloadsIn: [libraryId], forUpload: [libraryId: forUpload])

                // Annotations are not guaranteed to exist and they can be removed even if the parent PDF was not deleted due to upload state.
                // These are generated on device, so they'll just be recreated.
                try? fileStorage.remove(Files.annotationPreviews(for: libraryId))
                // Cleanup page thumbnails
                try? fileStorage.remove(Files.pageThumbnails(for: libraryId))

                if let keys = deletedIndividually[libraryId], !keys.isEmpty {
                    return .allForItems(keys, libraryId)
                }
                return .library(libraryId)
            } catch let error {
                DDLogError("AttachmentFileCleanupController: can't remove library downloads - \(error)")
                return nil
            }
        }

        /// Tries deleting given attachment.
        /// - parameter attachment: Attachment to delete.
        /// - returns: `true` if file could be deleted, `false` otherwise.
        func delete(attachment: Attachment) -> Bool {
            do {
                // Don't delete linked files
                guard case .file(_, _, _, let linkType, _) = attachment.type, linkType != .linkedFile else { return false }

                var canDelete: Bool = false

                try dbStorage.perform(on: queue, with: { coordinator in
                    let item = try coordinator.perform(request: ReadItemDbRequest(libraryId: attachment.libraryId, key: attachment.key))
                    let attachmentNeedsSync = item.attachmentNeedsSync

                    // Don't delete attachments that need to sync
                    guard !attachmentNeedsSync else {
                        canDelete = false
                        return
                    }

                    try? coordinator.perform(request: MarkFileAsDownloadedDbRequest(key: attachment.key, libraryId: attachment.libraryId, downloaded: false))

                    coordinator.invalidate()

                    canDelete = true
                })

                if canDelete {
                    try? removeFiles(for: attachment.key, libraryId: attachment.libraryId)
                }

                return canDelete
            } catch let error {
                DDLogError("AttachmentFileCleanupController: can't remove attachment file - \(error)")
                return false
            }
        }

        /// Deletes downloads in given libraries, but keeps files queued for upload intact.
        /// - parameter libraries: Libraries to delete from.
        /// - parameter forUpload: Keys of items which need upload for given libraries.
        /// - returns: Returns individual keys for given libraries which were actually deleted. Some deletions are ignored if files are queued for upload.
        func delete(downloadsIn libraries: [LibraryIdentifier], forUpload: [LibraryIdentifier: [String]]) -> [LibraryIdentifier: Set<String>] {
            var deletedIndividually: [LibraryIdentifier: Set<String>] = [:]

            for libraryId in libraries {
                let keysForUpload = forUpload[libraryId, default: []]
                if keysForUpload.isEmpty {
                    // No items are queued for upload, just delete the whole directory. Ignore thrown error because some may not exist locally (user didn't download anything in given library yet).
                    try? fileStorage.remove(Files.downloads(for: libraryId))
                    continue
                }

                // If there are pending uploads, delete only directories with uploaded files. If no folders are stored locally just skip.
                guard let contents: [File] = try? fileStorage.contentsOfDirectory(at: Files.downloads(for: libraryId)) else { continue }

                var keys: Set<String> = []
                let toDelete = contents.filter({ file in
                    // Check whether it's item folder and whether upload is pending for given item.
                    guard file.relativeComponents.count == 3, let key = file.relativeComponents.last, key.count == KeyGenerator.length else {
                        // If it's something else, just delete it.
                        return true
                    }
                    guard !keysForUpload.contains(key) else { return false }
                    // Delete it and record it's key.
                    keys.insert(key)
                    return true
                })
                deletedIndividually[libraryId] = keys

                for file in toDelete {
                    do {
                        try fileStorage.remove(file)
                    } catch let error {
                        DDLogError("AttachmentFileCleanupController: could not remove file \(file) - \(error)")
                    }
                }
            }

            return deletedIndividually
        }

        func removeFiles(for key: String, libraryId: LibraryIdentifier) throws {
            try fileStorage.remove(Files.attachmentDirectory(in: libraryId, key: key))
            // Annotations are not guaranteed to exist.
            try? fileStorage.remove(Files.annotationPreviews(for: key, libraryId: libraryId))
            // Cleanup page thumbnails
            try? fileStorage.remove(Files.pageThumbnails(for: key, libraryId: libraryId))
        }
    }
}
