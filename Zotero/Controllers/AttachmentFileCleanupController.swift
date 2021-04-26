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
        case library(LibraryIdentifier)
        case all

        var notification: AttachmentFileDeletedNotification {
            switch self {
            case .all: return .all
            case .library(let id): return .library(id)
            case .individual(let attachment, let parentKey): return .individual(key: attachment.key, parentKey: parentKey, libraryId: attachment.libraryId)
            }
        }
    }

    private unowned let fileStorage: FileStorage
    private unowned let dbStorage: DbStorage
    private let queue: DispatchQueue
    private let scheduler: SerialDispatchQueueScheduler
    private let disposeBag: DisposeBag

    init(fileStorage: FileStorage, dbStorage: DbStorage) {
        let queue = DispatchQueue(label: "org.zotero.FileCleanupQueue", qos: .userInitiated)
        self.fileStorage = fileStorage
        self.dbStorage = dbStorage
        self.scheduler = SerialDispatchQueueScheduler(queue: queue, internalSerialQueueName: "org.zotero.FileCleanupScheduler")
        self.queue = queue
        self.disposeBag = DisposeBag()

        NotificationCenter.default.rx
                                  .notification(.attachmentDeleted)
                                  .observeOn(self.scheduler)
                                  .subscribe(onNext: { [weak self] notification in
                                      if let file = notification.object as? File {
                                          self?.delete(file: file)
                                      }
                                  })
                                  .disposed(by: self.disposeBag)
    }

    private func delete(file: File) {
        // Don't need to check for errors, the attachment doesn't have to have the file downloaded locally, so this will throw for all attachments
        // without local files. If the file was not removed properly it can always be seen and done in settings.
        try? self.fileStorage.remove(file)
    }

    func delete(_ type: DeletionType, completed: ((Bool) -> Void)?) {
        self.queue.async {
            let result = self._delete(type)
            DispatchQueue.main.async {
                if result {
                    NotificationCenter.default.post(name: .attachmentFileDeleted, object: type.notification)
                }
                completed?(result)
            }
        }
    }

    private func _delete(_ type: DeletionType) -> Bool {
        switch type {
        case .all:
            do {
                try self.fileStorage.remove(Files.downloads)
                // Annotations are not guaranteed to exist
                try? self.fileStorage.remove(Files.annotationPreviews)
                try? self.fileStorage.remove(Files.cache)

                try? self.dbStorage.createCoordinator().perform(request: MarkAllFilesAsNotDownloadedDbRequest())
            } catch let error {
                DDLogError("AttachmentFileCleanupController: can't remove download directory - \(error)")
                return false
            }

        case .library(let libraryId):
            do {
                try self.fileStorage.remove(Files.downloads(for: libraryId))
                // Annotations are not guaranteed to exist
                try? self.fileStorage.remove(Files.annotationPreviews(for: libraryId))

                try? self.dbStorage.createCoordinator().perform(request: MarkLibraryFilesAsNotDownloadedDbRequest(libraryId: libraryId))
            } catch let error {
                DDLogError("AttachmentFileCleanupController: can't remove library downloads - \(error)")
                return false
            }

        case .individual(let attachment, _):
            do {
                switch attachment.type {
                case .file(_, _, _, let linkType):
                    // Don't try to delete linked files
                    guard linkType != .linkedFile else { return false }

                    try self.fileStorage.remove(Files.newAttachmentDirectory(in: attachment.libraryId, key: attachment.key))
                    // Annotations are not guaranteed to exist
                    try? self.fileStorage.remove(Files.annotationPreviews(for: attachment.key, libraryId: attachment.libraryId))

                    try? self.dbStorage.createCoordinator().perform(request: MarkFileAsDownloadedDbRequest(key: attachment.key, libraryId: attachment.libraryId, downloaded: false))
                case .url: return false
                }
            } catch let error {
                DDLogError("AttachmentFileCleanupController: can't remove attachment file - \(error)")
                return false
            }
        }
        
        return true
    }
}
