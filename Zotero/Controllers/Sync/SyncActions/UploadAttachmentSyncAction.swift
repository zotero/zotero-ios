//
//  UploadAttachmentSyncAction.swift
//  Zotero
//
//  Created by Michal Rentka on 30/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import Alamofire
import CocoaLumberjack
import RxAlamofire
import RxSwift

struct UploadAttachmentSyncAction: SyncAction {
    typealias Result = (Completable, Observable<RxProgress>) // Upload completion, Upload progress

    let key: String
    let file: File
    let filename: String
    let md5: String
    let mtime: Int
    let libraryId: LibraryIdentifier
    let userId: Int

    unowned let apiClient: ApiClient
    unowned let dbStorage: DbStorage
    unowned let fileStorage: FileStorage

    var result: Single<(Completable, Observable<RxProgress>)> {
        let dbCheck: Single<()> = Single.create { subscriber -> Disposable in
                                     do {
                                        let request = CheckItemIsChangedDbRequest(libraryId: self.libraryId, key: self.key)
                                          let isChanged = try self.dbStorage.createCoordinator().perform(request: request)
                                          if !isChanged {
                                              subscriber(.success(()))
                                          } else {
                                              subscriber(.error(SyncActionHandlerError.attachmentItemNotSubmitted))
                                          }
                                      } catch let error {
                                          subscriber(.error(error))
                                      }

                                      return Disposables.create()
                                  }

        let upload = dbCheck.flatMap { _ -> Single<UInt64> in
                                let size = self.fileStorage.size(of: self.file)
                                if size == 0 {
                                    return Single.error(SyncActionHandlerError.attachmentMissing)
                                } else {
                                    return Single.just(size)
                                }
                            }
                            .flatMap { filesize -> Single<AuthorizeUploadResponse> in
                                return AuthorizeUploadSyncAction(key: self.key, filename: self.filename, filesize: filesize,
                                                                 md5: self.md5, mtime: self.mtime, libraryId: self.libraryId,
                                                                 userId: self.userId, apiClient: self.apiClient).result
                            }
                            .flatMap { response -> Single<Swift.Result<(UploadRequest, String), SyncActionHandlerError>> in
                                switch response {
                                case .exists:
                                    return Single.just(.failure(SyncActionHandlerError.attachmentAlreadyUploaded))
                                case .new(let response):
                                    let request = AttachmentUploadRequest(url: response.url)
                                    return self.apiClient.upload(request: request) { data in
                                        response.params.forEach({ (key, value) in
                                            if let stringData = value.data(using: .utf8) {
                                                data.append(stringData, withName: key)
                                            }
                                        })
                                        data.append(self.file.createUrl(), withName: "file", fileName: self.filename, mimeType: self.file.mimeType)
                                    }.flatMap({ Single.just(.success(($0, response.uploadKey))) })
                                }
                            }

        let response = upload.flatMap({ result -> Single<Swift.Result<(Data, String), SyncActionHandlerError>> in
                                 switch result {
                                 case .success(let uploadRequest, let uploadKey):
                                      return uploadRequest.rx.data()
                                                             .asSingle()
                                                             .flatMap({ Single.just(.success(($0, uploadKey))) })
                                 case .failure(let error):
                                     return Single.just(.failure(error))
                                 }
                             })
                             .flatMap({ result -> Single<Swift.Result<(Data, ResponseHeaders), SyncActionHandlerError>> in
                                 switch result {
                                 case .success(_, let uploadKey):
                                     let request = RegisterUploadRequest(libraryId: self.libraryId,
                                                                         userId: self.userId,
                                                                         key: self.key,
                                                                         uploadKey: uploadKey)
                                     return self.apiClient.send(request: request).flatMap({ Single.just(.success($0)) })
                                 case .failure(let error):
                                     return Single.just(.failure(error))
                                 }
                             })
                             .flatMap({ result -> Single<()> in
                                 let markDbAction: () -> Single<()> = {
                                     do {
                                         let request = MarkAttachmentUploadedDbRequest(libraryId: self.libraryId, key: self.key)
                                         try self.dbStorage.createCoordinator().perform(request: request)
                                         return Single.just(())
                                     } catch let error {
                                         return Single.error(error)
                                     }
                                 }

                                 switch result {
                                 case .success:
                                     return markDbAction()
                                 case .failure(let error) where error == .attachmentAlreadyUploaded:
                                     return markDbAction()
                                 case .failure(let error):
                                     return Single.error(error)
                                 }
                             })
                             .asCompletable()

        let progress = upload.asObservable()
                             .flatMap({ result -> Observable<RxProgress> in
                                 switch result {
                                 case .success(let uploadRequest, _):
                                     return uploadRequest.rx.progress()
                                 case .failure(let error):
                                     return Observable.error(error)
                                 }
                             })
                             .do(onNext: { progress in
                                DDLogInfo("--- Upload progress: \(progress.completed) ---")
                             })

        return Single.just((response, progress))
    }
}
