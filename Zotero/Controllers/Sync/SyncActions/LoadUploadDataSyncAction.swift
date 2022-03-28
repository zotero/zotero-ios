//
//  LoadUploadDataSyncAction.swift
//  Zotero
//
//  Created by Michal Rentka on 30/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RxSwift

struct LoadUploadDataSyncAction: SyncAction {
    typealias Result = [AttachmentUpload]

    let libraryId: LibraryIdentifier

    unowned let backgroundUploaderContext: BackgroundUploaderContext
    unowned let dbStorage: DbStorage
    unowned let fileStorage: FileStorage

    var result: Single<[AttachmentUpload]> {
        return self.loadUploads(libraryId: self.libraryId)
                   .flatMap { uploads in
                       let backgroundUploads = self.backgroundUploaderContext.uploads.map({ $0.md5 })
                       return Single.just(uploads.filter({ !backgroundUploads.contains($0.md5) }))
                   }
    }

    private func loadUploads(libraryId: LibraryIdentifier) -> Single<[AttachmentUpload]> {
        return Single.create { subscriber -> Disposable in
            do {
                let request = ReadAttachmentUploadsDbRequest(libraryId: libraryId, fileStorage: self.fileStorage)
                let uploads = try self.dbStorage.perform(request: request, invalidateRealm: true)
                subscriber(.success(uploads))
            } catch let error {
                subscriber(.failure(error))
            }
            return Disposables.create()
        }
    }
}
