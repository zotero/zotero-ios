//
//  BackgroundUploadProcessor.swift
//  Zotero
//
//  Created by Michal Rentka on 08/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjack
import RxSwift

class BackgroundUploadProcessor {
    private let apiClient: ApiClient
    private let dbStorage: DbStorage
    private let fileStorage: FileStorage

    enum Error: Swift.Error {
        case expired
    }

    init(apiClient: ApiClient, dbStorage: DbStorage, fileStorage: FileStorage) {
        self.apiClient = apiClient
        self.dbStorage = dbStorage
        self.fileStorage = fileStorage
    }

    func finish(upload: BackgroundUpload) -> Observable<()> {
        let request = RegisterUploadRequest(libraryId: upload.libraryId,
                                            userId: upload.userId,
                                            key: upload.key,
                                            uploadKey: upload.uploadKey)
        return self.apiClient.send(request: request)
                             .flatMap { [weak self] _ -> Single<()> in
                                 guard let `self` = self else { return Single.error(Error.expired) }

                                 do {
                                     let request = MarkAttachmentUploadedDbRequest(libraryId: upload.libraryId, key: upload.key)
                                     try self.dbStorage.createCoordinator().perform(request: request)
                                     return Single.just(())
                                 } catch let error {
                                     return Single.error(error)
                                 }
                             }
                             .do(onSuccess: { [weak self] _ in
                                 self?.delete(file: Files.file(from: upload.fileUrl))
                             }, onError: { [weak self] _ in
                                 self?.delete(file: Files.file(from: upload.fileUrl))
                             })
                             .asObservable()
    }

    private func delete(file: File) {
        do {
            try self.fileStorage.remove(file)
        } catch let error {
            DDLogError("BackgroundUploadProcessor: can't remove uploaded file - \(error)")
        }
    }
}
