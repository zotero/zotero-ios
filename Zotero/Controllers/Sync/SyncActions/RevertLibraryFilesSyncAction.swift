//
//  RevertLibraryFilesSyncAction.swift
//  Zotero
//
//  Created by Michal Rentka on 13.06.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxSwift

struct RevertLibraryFilesSyncAction: SyncAction {
    typealias Result = ()

    let libraryId: LibraryIdentifier

    unowned let dbStorage: DbStorage
    unowned let fileStorage: FileStorage
    unowned let schemaController: SchemaController
    unowned let dateParser: DateParser
    let queue: DispatchQueue

    var result: Single<()> {
        return Single.create { subscriber -> Disposable in
            DDLogInfo("RevertLibraryFilesSyncAction: revert files to upload")

            do {
                let toUpload = try self.dbStorage.perform(request: ReadAllAttachmentUploadsDbRequest(libraryId: self.libraryId), on: self.queue)
                var cachedResponses: [ItemResponse] = []
                var failedKeys: [String] = []

                for item in toUpload {
                    do {
                        let file = Files.jsonCacheFile(for: .item, libraryId: self.libraryId, key: item.key)
                        let data = try self.fileStorage.read(file)
                        let jsonObject = try JSONSerialization.jsonObject(with: data, options: .allowFragments)

                        if let jsonData = jsonObject as? [String: Any] {
                            let response = try ItemResponse(response: jsonData, schemaController: self.schemaController)
                            cachedResponses.append(response)
                        } else {
                            failedKeys.append(item.key)
                        }
                    } catch let error {
                        DDLogError("RevertLibraryFilesSyncAction: can't load cached file - \(error)")
                        failedKeys.append(item.key)
                    }
                }

                DDLogInfo("RevertLibraryFilesSyncAction: loaded \(cachedResponses.count) cached items, missing \(failedKeys.count)")
                
                DDLogInfo("RevertLibraryFilesSyncAction: delete files which were not uploaded yet")
                for key in failedKeys {
                    let file = Files.attachmentDirectory(in: self.libraryId, key: key)
                    try? self.fileStorage.remove(file)
                }

                var changedFilenames: [StoreItemsResponse.FilenameChange] = []
                try self.dbStorage.perform(on: self.queue) { coordinator in
                    // Delete items that didn't sync before and weren't submitted to backend
                    DDLogError("RevertLibraryFilesSyncAction: delete failed keys")
                    try coordinator.perform(request: DeleteObjectsDbRequest<RItem>(keys: failedKeys, libraryId: self.libraryId))
                    // Store cached objects from backend to local database to get rid of local changes.
                    DDLogError("RevertLibraryFilesSyncAction: restore cached objects")
                    let request = StoreItemsDbResponseRequest(responses: cachedResponses, schemaController: self.schemaController, dateParser: self.dateParser, preferResponseData: true)
                    changedFilenames = try coordinator.perform(request: request).changedFilenames
                    coordinator.invalidate()
                }

                DDLogError("RevertLibraryFilesSyncAction: rename local files to match file names")
                self.renameExistingFiles(changes: changedFilenames, libraryId: self.libraryId)

                subscriber(.success(()))
            } catch let error {
                subscriber(.failure(error))
            }

            return Disposables.create()
        }
    }

    private func renameExistingFiles(changes: [StoreItemsResponse.FilenameChange], libraryId: LibraryIdentifier) {
        for change in changes {
            let oldFile = Files.attachmentFile(in: libraryId, key: change.key, filename: change.oldName, contentType: change.contentType)

            guard self.fileStorage.has(oldFile) else { continue }

            let newFile = Files.attachmentFile(in: libraryId, key: change.key, filename: change.newName, contentType: change.contentType)

            do {
                try self.fileStorage.move(from: oldFile, to: newFile)
            } catch let error {
                DDLogWarn("RevertLibraryFilesSyncAction: can't rename file - \(error)")
                // If it can't be moved, at least delete the old one. It'll have to be re-downloaded anyway.
                try? self.fileStorage.remove(oldFile)
                try? self.fileStorage.remove(newFile)
            }
        }
    }
}
