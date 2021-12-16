//
//  BackgroundUploaderRequestProvider.swift
//  Zotero
//
//  Created by Michal Rentka on 08/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import Alamofire
import CocoaLumberjackSwift
import RxSwift

final class BackgroundUploaderRequestProvider {
    enum Error: Swift.Error {
        case expired
    }

    private let fileStorage: FileStorage

    init(fileStorage: FileStorage) {
        self.fileStorage = fileStorage
    }

    func createRequest(for upload: BackgroundUpload, filename: String, mimeType: String, parameters: [String: String]?, headers: [String: String]?, schemaVersion: Int) -> Single<(URLRequest, URL, Int64)> {
        switch upload.type {
        case .webdav:
            return self.createPutRequest(for: upload)
                       .flatMap({ request in
                           let size = self.fileStorage.size(of: Files.file(from: upload.fileUrl))
                           return Single.just((request, upload.fileUrl, Int64(size)))
                       })
        case .zotero:
            return self.createMultipartformRequest(for: upload, filename: filename, mimeType: mimeType, parameters: parameters, headers: headers, schemaVersion: schemaVersion)
                       .flatMap({ request, url in
                           let size = self.fileStorage.size(of: Files.file(from: url))
                           return Single.just((request, url, Int64(size)))
                       })
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
    func createMultipartformRequest(for upload: BackgroundUpload, filename: String, mimeType: String, parameters: [String: String]?, headers: [String: String]?, schemaVersion: Int) -> Single<(URLRequest, URL)> {
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
                request.setValue(ApiConstants.version.description, forHTTPHeaderField: "Zotero-API-Version")
                request.setValue("\(schemaVersion)", forHTTPHeaderField: "Zotero-Schema-Version")
                try request.validate()

                subscriber(.success((request, newFileUrl)))
            } catch let error {
                DDLogError("BackgroundUploadProcessor: can't create multipartform data - \(error)")
                subscriber(.failure(error))
            }

            return Disposables.create()
        }
    }

    func createPutRequest(for upload: BackgroundUpload) -> Single<URLRequest> {
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
}
