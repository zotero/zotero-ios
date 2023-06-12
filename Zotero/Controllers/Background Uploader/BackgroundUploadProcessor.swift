//
//  BackgroundUploadProcessor.swift
//  Zotero
//
//  Created by Michal Rentka on 15.12.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxSwift

final class BackgroundUploadProcessor {
    enum Error: Swift.Error {
        case expired
        case cantSubmitItem
    }

    private let apiClient: ApiClient
    private let dbStorage: DbStorage
    private let fileStorage: FileStorage
    private let webDavController: WebDavController

    init(apiClient: ApiClient, dbStorage: DbStorage, fileStorage: FileStorage, webDavController: WebDavController) {
        self.apiClient = apiClient
        self.dbStorage = dbStorage
        self.fileStorage = fileStorage
        self.webDavController = webDavController
    }

    func finish(upload: BackgroundUpload, successful: Bool, queue: DispatchQueue, scheduler: SerialDispatchQueueScheduler) -> Observable<()> {
        if !successful {
            // If upload failed, remove temporary upload data (multipartform in case of ZFS, zip in case of WebDAV).
            return Observable.create { [weak self] subscriber in
                self?.delete(file: Files.file(from: upload.fileUrl))

                subscriber.on(.next(()))
                subscriber.on(.completed)

                return Disposables.create()
            }
        }

        switch upload.type {
        case .zotero(let uploadKey):
            return self.finishZoteroUpload(uploadKey: uploadKey, key: upload.key, libraryId: upload.libraryId, fileUrl: upload.fileUrl, userId: upload.userId, queue: queue, scheduler: scheduler)
        case .webdav(let mtime):
            return self.finishWebdavUpload(key: upload.key, libraryId: upload.libraryId, mtime: mtime, md5: upload.md5, userId: upload.userId,
                                           fileUrl: upload.fileUrl, webDavUrl: upload.remoteUrl, queue: queue, scheduler: scheduler)
        }
    }

    private func finishZoteroUpload(uploadKey: String, key: String, libraryId: LibraryIdentifier, fileUrl: URL, userId: Int,
                                    queue: DispatchQueue, scheduler: SerialDispatchQueueScheduler) -> Observable<()> {
        let request = RegisterUploadRequest(libraryId: libraryId, userId: userId, key: key, uploadKey: uploadKey, oldMd5: nil)
        return self.apiClient.send(request: request, queue: queue)
                             .observe(on: scheduler)
                             .flatMap { [weak self] _, response -> Single<()> in
                                 guard let self = self else { return Single.error(Error.expired) }
                                 return self.markAttachmentAsUploaded(version: response.allHeaderFields.lastModifiedVersion, key: key, libraryId: libraryId, queue: queue)
                             }
                             .do(onSuccess: { [weak self] _ in
                                 // Remove temporary upload file created in `createMultipartformRequest`
                                 self?.delete(file: Files.file(from: fileUrl))
                             }, onError: { [weak self] _ in
                                 // Remove temporary upload file created in `createMultipartformRequest`
                                 self?.delete(file: Files.file(from: fileUrl))
                             })
                             .asObservable()
    }

    private func delete(file: File) {
        do {
            DDLogInfo("BackgroundUploadProcessor: delete file after upload - \(file.createUrl().path)")
            try self.fileStorage.remove(file)
        } catch let error {
            DDLogError("BackgroundUploadProcessor: can't remove uploaded file - \(error)")
        }
    }

    private func finishWebdavUpload(key: String, libraryId: LibraryIdentifier, mtime: Int, md5: String, userId: Int, fileUrl: URL, webDavUrl: URL,
                                    queue: DispatchQueue, scheduler: SerialDispatchQueueScheduler) -> Observable<()> {
        // Don't need to delete ZIP file here, because background upload creates temporary file for upload and the zip file is deleted after background upload is enqueued.
        return self.webDavController.finishUpload(key: key, result: .success((mtime, md5, webDavUrl)), file: nil, queue: queue)
                   .observe(on: scheduler)
                   .flatMap({
                       return self.submitItemWithHashAndMtime(key: key, libraryId: libraryId, mtime: mtime, md5: md5, userId: userId, queue: queue)
                   })
                   .flatMap({ version in
                       return self.markAttachmentAsUploaded(version: version, key: key, libraryId: libraryId, queue: queue)
                   })
                   .do(onSuccess: { [weak self] _ in
                       // Remove temporary upload zip file created by webdav controller
                       self?.delete(file: Files.file(from: fileUrl))
                   }, onError: { [weak self] _ in
                       // Remove temporary upload zip file created by webdav controller
                       self?.delete(file: Files.file(from: fileUrl))
                   })
                   .asObservable()
    }

    private func submitItemWithHashAndMtime(key: String, libraryId: LibraryIdentifier, mtime: Int, md5: String, userId: Int, queue: DispatchQueue) -> Single<Int> {
        DDLogInfo("BackgroundUploadProcessor: submit mtime and md5")

        let loadParameters: Single<[String: Any]> = Single.create { subscriber -> Disposable in
            do {
                let item = try self.dbStorage.perform(request: ReadItemDbRequest(libraryId: libraryId, key: key), on: queue)
                let parameters = item.mtimeAndHashParameters
                item.realm?.invalidate()
                subscriber(.success(parameters))
            } catch let error {
                subscriber(.failure(error))
                DDLogError("BackgroundUploadProcessor: can't load params - \(error)")
                return Disposables.create()
            }
            return Disposables.create()
        }

        return loadParameters.flatMap { parameters -> Single<(Data, HTTPURLResponse)> in
            let request = UpdatesRequest(libraryId: libraryId, userId: userId, objectType: .item, params: [parameters], version: nil)
            return self.apiClient.send(request: request, queue: queue).mapData(httpMethod: request.httpMethod.rawValue)
        }
        .flatMap({ data, response -> Single<(UpdatesResponse, Int)> in
            do {
                let newVersion = response.allHeaderFields.lastModifiedVersion
                let json = try JSONSerialization.jsonObject(with: data, options: .allowFragments)
                return Single.just((try UpdatesResponse(json: json, keys: [key]), newVersion))
            } catch let error {
                return Single.error(error)
            }
        })
        .flatMap({ response, newVersion -> Single<Int> in
            if !response.failed.isEmpty {
                return Single.error(Error.cantSubmitItem)
            }
            return Single.just(newVersion)
        })
    }

    private func markAttachmentAsUploaded(version: Int, key: String, libraryId: LibraryIdentifier, queue: DispatchQueue) -> Single<()> {
        return Single.create { subscriber -> Disposable in
            DDLogInfo("BackgroundUploadProcessor: mark as uploaded")

            do {
                try self.dbStorage.perform(request: MarkAttachmentUploadedDbRequest(libraryId: libraryId, key: key, version: version), on: queue)
                subscriber(.success(()))
            } catch let error {
                DDLogError("BackgroundUploadProcessor: can't mark attachment as uploaded - \(error)")
                subscriber(.failure(error))
            }

            return Disposables.create()
        }
    }
}
