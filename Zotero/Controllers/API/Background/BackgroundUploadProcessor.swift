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

    enum Error: Swift.Error {
        case expired
    }

    init(apiClient: ApiClient, dbStorage: DbStorage, fileStorage: FileStorage) {
        self.apiClient = apiClient
        self.dbStorage = dbStorage
        self.fileStorage = fileStorage
    }

    /// Creates a multipartform request for a file upload. The original file is copied to another folder so that it can be streamed from it.
    /// It needs to be deleted once the upload finishes (successful or not).
    /// - parameter upload: Backgroud upload to prepare
    /// - parameter filename: Filename for file to upload
    /// - parameter mimeType: Mimetype of file to upload
    /// - parameter parameters: Extra parameters for upload
    /// - parameter headers: Headers to be sent with the upload request
    /// - returns: Returns a `Single` with properly formed `URLRequest` and `URL` pointing to file, which should be uploaded.
    func createMultipartformRequest(for upload: BackgroundUpload, filename: String, mimeType: String, parameters: [String: String]?,
                                    headers: [String: String]?) -> Single<(URLRequest, URL)> {
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

            let newFile = Files.temporaryUploadFile
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

    func finish(upload: BackgroundUpload) -> Observable<()> {
        switch upload.type {
        case .zotero(let uploadKey):
            return self.finishZoteroUpload(uploadKey: uploadKey, key: upload.key, libraryId: upload.libraryId, fileUrl: upload.fileUrl, userId: upload.userId)
        case .webdav(let mtime):
            return self.finishWebdavUpload(key: upload.key, libraryId: upload.libraryId, mtime: mtime, md5: upload.md5, userId: upload.userId)
        }
    }

    private func finishZoteroUpload(uploadKey: String, key: String, libraryId: LibraryIdentifier, fileUrl: URL, userId: Int) -> Observable<()> {
        let request = RegisterUploadRequest(libraryId: libraryId, userId: userId, key: key, uploadKey: uploadKey, oldMd5: nil)
        return self.apiClient.send(request: request)
                             .flatMap { [weak self] _ -> Single<()> in
                                 guard let `self` = self else { return Single.error(Error.expired) }

                                 do {
                                     let request = MarkAttachmentUploadedDbRequest(libraryId: libraryId, key: key)
                                     try self.dbStorage.createCoordinator().perform(request: request)
                                     return Single.just(())
                                 } catch let error {
                                     return Single.error(error)
                                 }
                             }
                             .do(onSuccess: { [weak self] _ in
                                 self?.delete(file: Files.file(from: fileUrl))
                             }, onError: { [weak self] _ in
                                 self?.delete(file: Files.file(from: fileUrl))
                             })
                             .asObservable()
    }

    private func finishWebdavUpload(key: String, libraryId: LibraryIdentifier, mtime: Int, md5: String, userId: Int) -> Observable<()> {
        return Observable.just(())
    }

    private func delete(file: File) {
        do {
            try self.fileStorage.remove(file)
        } catch let error {
            DDLogError("BackgroundUploadProcessor: can't remove uploaded file - \(error)")
        }
    }
}
