//
//  UploadAttachmentSyncAction.swift
//  Zotero
//
//  Created by Michal Rentka on 30/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import Alamofire
import CocoaLumberjackSwift
import RxSwift

class UploadAttachmentSyncAction: SyncAction {
    typealias Result = ()

    let key: String
    let file: File
    let filename: String
    let md5: String
    let mtime: Int
    let libraryId: LibraryIdentifier
    let userId: Int
    let oldMd5: String?

    unowned let apiClient: ApiClient
    unowned let dbStorage: DbStorage
    unowned let fileStorage: FileStorage
    unowned let webDavController: WebDavController
    let queue: DispatchQueue
    let scheduler: SchedulerType
    let disposeBag: DisposeBag

    /// Indicates whether this action has failed performing before it could submit anything to Zotero backend. It could happen that we have only attachment upload enqueued, there are remote changes
    /// on Zotero backend, but since the upload failed before it talked to the backend, remote changes would be ignored (no 412 received, no download actions added to queue, issue #381).
    var failedBeforeZoteroApiRequest: Bool

    init(key: String, file: File, filename: String, md5: String, mtime: Int, libraryId: LibraryIdentifier, userId: Int, oldMd5: String?, apiClient: ApiClient, dbStorage: DbStorage,
         fileStorage: FileStorage, webDavController: WebDavController, queue: DispatchQueue, scheduler: SchedulerType, disposeBag: DisposeBag) {
        self.key = key
        self.file = file
        self.filename = filename
        self.md5 = md5
        self.mtime = mtime
        self.libraryId = libraryId
        self.userId = userId
        self.oldMd5 = oldMd5
        self.apiClient = apiClient
        self.dbStorage = dbStorage
        self.fileStorage = fileStorage
        self.webDavController = webDavController
        self.queue = queue
        self.scheduler = scheduler
        self.disposeBag = disposeBag
        self.failedBeforeZoteroApiRequest = true
    }

    var result: Single<()> {
        switch self.libraryId {
        case .custom:
            return self.webDavController.sessionStorage.isEnabled ? self.webDavResult : self.zoteroResult
        case .group:
            return self.zoteroResult
        }
    }

    private var zoteroResult: Single<()> {
        DDLogInfo("UploadAttachmentSyncAction: upload to ZFS")

        return self.checkDatabase()
                   .flatMap { _ -> Single<UInt64> in
                       return self.validateFile()
                   }
                   .flatMap { filesize -> Single<AuthorizeUploadResponse> in
                       self.failedBeforeZoteroApiRequest = false
                       return AuthorizeUploadSyncAction(key: self.key, filename: self.filename, filesize: filesize, md5: self.md5, mtime: self.mtime, libraryId: self.libraryId,
                                                        userId: self.userId, oldMd5: self.oldMd5, apiClient: self.apiClient, queue: self.queue, scheduler: self.scheduler).result
                   }
                   .observe(on: self.scheduler)
                   .flatMap { response -> Single<String> in
                       switch response {
                       case .exists(let version):
                           DDLogInfo("UploadAttachmentSyncAction: file exists remotely")
                           return self.markAttachmentAsUploaded(version: version).flatMap({ Single.error(SyncActionError.attachmentAlreadyUploaded) })

                       case .new(let response):
                           DDLogInfo("UploadAttachmentSyncAction: file needs upload")
                           let request = AttachmentUploadRequest(endpoint: .other(response.url), httpMethod: .post, headers: ["If-None-Match": "*"])
                           return self.apiClient.upload(request: request, queue: self.queue, multipartFormData: { data in
                               response.params.forEach({ (key, value) in
                                   if let stringData = value.data(using: .utf8) {
                                       data.append(stringData, withName: key)
                                   }
                               })
                               data.append(self.file.createUrl(), withName: "file", fileName: self.filename, mimeType: self.file.mimeType)
                           })
                           .flatMap({ _ in Single.just(response.uploadKey) })
                       }
                   }
                   .observe(on: self.scheduler)
                   .flatMap({ uploadKey -> Single<HTTPURLResponse> in
                       DDLogInfo("UploadAttachmentSyncAction: register upload")
                       let request = RegisterUploadRequest(libraryId: self.libraryId, userId: self.userId, key: self.key, uploadKey: uploadKey, oldMd5: self.oldMd5)
                       return self.apiClient.send(request: request, queue: self.queue).flatMap({ Single.just($0.1) })
                   })
                   .observe(on: self.scheduler)
                   .flatMap({ response -> Single<()> in
                       return self.markAttachmentAsUploaded(version: response.allHeaderFields.lastModifiedVersion)
                   })
                   .do(onError: { error in
                       if let error = error as? SyncActionError {
                           switch error {
                           case .attachmentAlreadyUploaded: return
                           default: break
                           }
                       }
                       DDLogError("UploadAttachmentSyncAction: could not upload - \(error)")
                   })
    }

    private var webDavResult: Single<()> {
        DDLogInfo("UploadAttachmentSyncAction: upload to WebDAV")

        var file: File?
        return self.checkDatabase()
                   .flatMap { _ -> Single<UInt64> in
                       return self.validateFile()
                   }
                   .flatMap { filesize -> Single<WebDavUploadResult> in
                       return self.webDavController.prepareForUpload(key: self.key, mtime: self.mtime, hash: self.md5, file: self.file, queue: self.queue)
                   }
                   .observe(on: self.scheduler)
                   .flatMap { response -> Single<URL> in
                       switch response {
                       case .exists:
                           DDLogInfo("UploadAttachmentSyncAction: file exists remotely")
                           return self.markAttachmentAsUploaded(version: nil).flatMap({ Single.error(SyncActionError.attachmentAlreadyUploaded) })

                       case .new(let url, let newFile):
                           DDLogInfo("UploadAttachmentSyncAction: file needs upload")
                           file = newFile

                           let request = AttachmentUploadRequest(endpoint: .webDav(url.appendingPathComponent(self.key + ".zip")), httpMethod: .put, logParams: .headers)
                           return self.webDavController.upload(request: request, fromFile: newFile, queue: self.queue)
                                      .flatMap({ _ in Single.just(url) })
                       }
                   }
                   .observe(on: self.scheduler)
                   .do(onError: { error in
                       guard let file = file else { return }
                       // If something broke during upload, remove tmp zip file
                       self.webDavController.finishUpload(key: self.key, result: .failure(error), file: file, queue: self.queue)
                           .subscribe(on: self.scheduler)
                           .subscribe()
                           .disposed(by: self.disposeBag)
                   })
                   .flatMap({ url -> Single<()> in
                       return self.webDavController.finishUpload(key: self.key, result: .success((self.mtime, self.md5, url)), file: file, queue: self.queue)
                   })
                   .flatMap({ _ -> Single<Int> in
                       return self.submitItemWithHashAndMtime().flatMap({ Single.just($0) })
                   })
                   .observe(on: self.scheduler)
                   .flatMap({ version -> Single<()> in
                       return self.markAttachmentAsUploaded(version: version)
                   })
                   .do(onError: { error in
                       if let error = error as? SyncActionError {
                           switch error {
                           case .attachmentAlreadyUploaded: return
                           default: break
                           }
                       }
                       DDLogError("UploadAttachmentSyncAction: could not upload - \(error)")
                   })
    }

    private func submitItemWithHashAndMtime() -> Single<Int> {
        DDLogInfo("UploadAttachmentSyncAction: submit mtime and md5")

        let loadParameters: Single<[String: Any]> = Single.create { subscriber -> Disposable in
            do {
                let item = try self.dbStorage.createCoordinator().perform(request: ReadItemDbRequest(libraryId: self.libraryId, key: self.key))
                subscriber(.success(item.mtimeAndHashParameters))
            } catch let error {
                subscriber(.failure(error))
                DDLogError("UploadAttachmentSyncAction: can't load params - \(error)")
                return Disposables.create()
            }
            return Disposables.create()
        }

        return loadParameters.flatMap { params -> Single<(Int, Error?)> in
            self.failedBeforeZoteroApiRequest = false
            return SubmitUpdateSyncAction(parameters: [params], sinceVersion: nil, object: .item, libraryId: self.libraryId, userId: self.userId, updateLibraryVersion: false,
                                          apiClient: self.apiClient, dbStorage: self.dbStorage, fileStorage: self.fileStorage, queue: self.queue, scheduler: self.scheduler).result
        }
        .flatMap { version, error -> Single<Int> in
            if let error = error {
                return Single.error(error)
            } else {
                return Single.just(version)
            }
        }
    }

    private func markAttachmentAsUploaded(version: Int?) -> Single<()> {
        return Single.create { subscriber -> Disposable in
            DDLogInfo("UploadAttachmentSyncAction: mark as uploaded")

            do {
                var requests: [DbRequest] = [MarkAttachmentUploadedDbRequest(libraryId: self.libraryId, key: self.key, version: version)]
                if let version = version {
                    requests.append(UpdateVersionsDbRequest(version: version, libraryId: self.libraryId, type: .object(.item)))
                }

                try self.dbStorage.createCoordinator().perform(requests: requests)

                subscriber(.success(()))
            } catch let error {
                DDLogError("UploadAttachmentSyncAction: can't mark attachment as uploaded - \(error)")
                subscriber(.failure(error))
            }

            return Disposables.create()
        }
    }

    private func checkDatabase() -> Single<()> {
        return Single.create { subscriber -> Disposable in
            DDLogInfo("UploadAttachmentSyncAction: check whether attachment item has been submitted")

            do {
                let request = CheckItemIsChangedDbRequest(libraryId: self.libraryId, key: self.key)
                let isChanged = try self.dbStorage.createCoordinator().perform(request: request)
                if !isChanged {
                    subscriber(.success(()))
                } else {
                    DDLogError("UploadAttachmentSyncAction: attachment item not submitted")
                    subscriber(.failure(SyncActionError.attachmentItemNotSubmitted))
                }
            } catch let error {
                DDLogError("UploadAttachmentSyncAction: could not check item submitted - \(error)")
                subscriber(.failure(error))
            }

            return Disposables.create()
        }
    }

    private func validateFile() -> Single<UInt64> {
        return Single.create { subscriber -> Disposable in
            DDLogInfo("UploadAttachmentSyncAction: validate file to upload")

            let size = self.fileStorage.size(of: self.file)

            if size > 0 {
                subscriber(.success(size))
            } else {
                DDLogError("UploadAttachmentSyncAction: missing attachment - \(self.file.createUrl().absoluteString)")
                let item = try? self.dbStorage.createCoordinator().perform(request: ReadItemDbRequest(libraryId: self.libraryId, key: self.key))
                let title = item?.displayTitle ?? L10n.notFound
                subscriber(.failure(SyncActionError.attachmentMissing(key: self.key, libraryId: self.libraryId, title: title)))
            }

            return Disposables.create()
        }
    }
}
