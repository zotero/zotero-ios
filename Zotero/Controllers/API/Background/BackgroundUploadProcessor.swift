//
//  BackgroundUploadProcessor.swift
//  Zotero
//
//  Created by Michal Rentka on 08/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import Alamofire
import CocoaLumberjackSwift
import RxSwift

final class BackgroundUploadProcessor {
    private let apiClient: ApiClient
    private let dbStorage: DbStorage
    private let fileStorage: FileStorage
    private let webDavController: WebDavController

    enum Error: Swift.Error {
        case expired
        case cantSubmitItem
    }

    init(apiClient: ApiClient, dbStorage: DbStorage, fileStorage: FileStorage, webDavController: WebDavController) {
        self.apiClient = apiClient
        self.dbStorage = dbStorage
        self.fileStorage = fileStorage
        self.webDavController = webDavController
    }

    func createRequest(for upload: BackgroundUpload, filename: String, mimeType: String, parameters: [String: String]?, headers: [String: String]?) -> Single<(URLRequest, URL)> {
        switch upload.type {
        case .webdav:
            return self.createPutRequest(for: upload, filename: filename, mimeType: mimeType).flatMap({ Single.just(($0, upload.fileUrl)) })
        case .zotero:
            return self.createMultipartformRequest(for: upload, filename: filename, mimeType: mimeType, parameters: parameters, headers: headers)
        }
    }

    /// Creates a multipartform request for a file upload. The original file is copied to another folder so that it can be streamed from it.
    /// It needs to be deleted once the upload finishes (successful or not).
    /// - parameter upload: Backgroud upload to prepare
    /// - parameter filename: Filename for file to upload
    /// - parameter mimeType: Mimetype of file to upload
    /// - parameter parameters: Extra parameters for upload
    /// - parameter headers: Headers to be sent with the upload request
    /// - returns: Returns a `Single` with properly formed `URLRequest` and `URL` pointing to file, which should be uploaded.
    func createMultipartformRequest(for upload: BackgroundUpload, filename: String, mimeType: String, parameters: [String: String]?, headers: [String: String]?) -> Single<(URLRequest, URL)> {
        return Single.create { [weak self] subscriber -> Disposable in
            guard let `self` = self else {
                subscriber(.failure(Error.expired))
                return Disposables.create()
            }

            let formData = MultipartFormData(fileManager: self.fileStorage.fileManager)
            if let parameters = parameters {
                // Append parameters to the multipartform request.
                parameters.forEach { (key, value) in
                    if let stringData = value.data(using: .utf8) {
                        formData.append(stringData, withName: key)
                    }
                }
            }
            formData.append(upload.fileUrl, withName: "file", fileName: filename, mimeType: mimeType)

            let newFile = Files.temporaryMultipartformUploadFile
            let newFileUrl = newFile.createUrl()

            do {
                // Create temporary file for upload and write multipartform data to it.
                try self.fileStorage.createDirectories(for: newFile)
                try formData.writeEncodedData(to: newFileUrl)
                // Create upload request and validate it.
                var request = try URLRequest(url: upload.remoteUrl, method: .post, headers: headers.flatMap(HTTPHeaders.init))
                request.setValue(formData.contentType, forHTTPHeaderField: "Content-Type")
                try request.validate()

                subscriber(.success((request, newFileUrl)))
            } catch let error {
                DDLogError("BackgroundUploadProcessor: can't create multipartform data - \(error)")
                subscriber(.failure(error))
            }

            return Disposables.create()
        }
    }

    func createPutRequest(for upload: BackgroundUpload, filename: String, mimeType: String) -> Single<URLRequest> {
        return Single.create { subscriber -> Disposable in
            do {
                // Create upload request and validate it.
                let request = try URLRequest(url: upload.remoteUrl.appendingPathComponent(upload.key + ".zip"), method: .put)
                try request.validate()

                subscriber(.success(request))
            } catch let error {
                DDLogError("BackgroundUploadProcessor: can't create multipartform data - \(error)")
                subscriber(.failure(error))
            }

            return Disposables.create()
        }
    }

    func finish(upload: BackgroundUpload, successful: Bool) -> Observable<()> {
        if !successful {
            // If upload failed, remove temporary upload data (multipartform in case of ZFS, zip in case of WebDAV).
            self.delete(file: Files.file(from: upload.fileUrl))
        }

        switch upload.type {
        case .zotero(let uploadKey):
            return self.finishZoteroUpload(uploadKey: uploadKey, key: upload.key, libraryId: upload.libraryId, fileUrl: upload.fileUrl, userId: upload.userId)
        case .webdav(let mtime):
            return self.finishWebdavUpload(key: upload.key, libraryId: upload.libraryId, mtime: mtime, md5: upload.md5, userId: upload.userId, fileUrl: upload.fileUrl, webDavUrl: upload.remoteUrl)
        }
    }

    private func finishZoteroUpload(uploadKey: String, key: String, libraryId: LibraryIdentifier, fileUrl: URL, userId: Int) -> Observable<()> {
        let request = RegisterUploadRequest(libraryId: libraryId, userId: userId, key: key, uploadKey: uploadKey, oldMd5: nil)
        return self.apiClient.send(request: request)
                             .flatMap { [weak self] data, response -> Single<()> in
                                 guard let `self` = self else { return Single.error(Error.expired) }
                                 return self.markAttachmentAsUploaded(version: response.allHeaderFields.lastModifiedVersion, key: key, libraryId: libraryId)
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
            try self.fileStorage.remove(file)
        } catch let error {
            DDLogError("BackgroundUploadProcessor: can't remove uploaded file - \(error)")
        }
    }

    private func finishWebdavUpload(key: String, libraryId: LibraryIdentifier, mtime: Int, md5: String, userId: Int, fileUrl: URL, webDavUrl: URL) -> Observable<()> {
        // Don't need to delete ZIP file here, because background upload creates temporary file for upload and the zip file is deleted after background upload is enqueued.
        return self.webDavController.finishUpload(key: key, result: .success((mtime, md5, webDavUrl)), file: nil, queue: .main)
                   .flatMap({
                       return self.submitItemWithHashAndMtime(key: key, libraryId: libraryId, mtime: mtime, md5: md5, userId: userId)
                   })
                   .flatMap({ version in
                       return self.markAttachmentAsUploaded(version: version, key: key, libraryId: libraryId)
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

    private func submitItemWithHashAndMtime(key: String, libraryId: LibraryIdentifier, mtime: Int, md5: String, userId: Int) -> Single<Int> {
        DDLogInfo("BackgroundUploadProcessor: submit mtime and md5")

        let loadParameters: Single<[String: Any]> = Single.create { subscriber -> Disposable in
            do {
                let item = try self.dbStorage.createCoordinator().perform(request: ReadItemDbRequest(libraryId: libraryId, key: key))
                subscriber(.success(item.mtimeAndHashParameters))
            } catch let error {
                subscriber(.failure(error))
                DDLogError("BackgroundUploadProcessor: can't load params - \(error)")
                return Disposables.create()
            }
            return Disposables.create()
        }

        return loadParameters.flatMap { parameters -> Single<(Data, HTTPURLResponse)> in
            let request = UpdatesRequest(libraryId: libraryId, userId: userId, objectType: .item, params: [parameters], version: nil)
            return self.apiClient.send(request: request)
        }
        .flatMap({ data, response -> Single<(UpdatesResponse, Int)> in
            do {
                let newVersion = response.allHeaderFields.lastModifiedVersion
                let json = try JSONSerialization.jsonObject(with: data, options: .allowFragments)
                return Single.just((try UpdatesResponse(json: json), newVersion))
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

    private func markAttachmentAsUploaded(version: Int, key: String, libraryId: LibraryIdentifier) -> Single<()> {
        return Single.create { subscriber -> Disposable in
            DDLogInfo("BackgroundUploadProcessor: mark as uploaded")

            do {
                let requests: [DbRequest] = [MarkAttachmentUploadedDbRequest(libraryId: libraryId, key: key, version: version),
                                             UpdateVersionsDbRequest(version: version, libraryId: libraryId, type: .object(.item))]
                try self.dbStorage.createCoordinator().perform(requests: requests)
                subscriber(.success(()))
            } catch let error {
                DDLogError("BackgroundUploadProcessor: can't mark attachment as uploaded - \(error)")
                subscriber(.failure(error))
            }

            return Disposables.create()
        }
    }
}
