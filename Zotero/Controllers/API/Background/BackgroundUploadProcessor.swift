//
//  BackgroundUploadProcessor.swift
//  Zotero
//
//  Created by Michal Rentka on 08/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RxSwift

class BackgroundUploadProcessor {
    private let apiClient: ApiClient
    private let dbStorage: DbStorage

    enum Error: Swift.Error {
        case expired
    }

    init(apiClient: ApiClient, dbStorage: DbStorage) {
        self.apiClient = apiClient
        self.dbStorage = dbStorage
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
                            .asObservable()
    }
}
