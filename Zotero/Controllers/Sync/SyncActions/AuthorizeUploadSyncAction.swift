//
//  AuthorizeUploadSyncAction.swift
//  Zotero
//
//  Created by Michal Rentka on 30/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxSwift

struct AuthorizeUploadSyncAction: SyncAction {
    typealias Result = AuthorizeUploadResponse

    let key: String
    let filename: String
    let filesize: UInt64
    let md5: String
    let mtime: Int
    let libraryId: LibraryIdentifier
    let userId: Int
    let oldMd5: String?

    unowned let apiClient: ApiClient
    let queue: DispatchQueue
    let scheduler: SchedulerType

    var result: Single<AuthorizeUploadResponse> {
        DDLogInfo("AuthorizeUploadSyncAction: authorize upload")
        let request = AuthorizeUploadRequest(libraryId: self.libraryId, userId: self.userId, key: self.key, filename: self.filename,
                                             filesize: self.filesize, md5: self.md5, mtime: self.mtime, oldMd5: self.oldMd5)
        return self.apiClient.send(request: request, queue: self.queue)
                             .observe(on: self.scheduler)
                             .flatMap { (data, response) -> Single<AuthorizeUploadResponse> in
                                do {
                                    let jsonObject = try JSONSerialization.jsonObject(with: data, options: .allowFragments)
                                    let response = try AuthorizeUploadResponse(from: jsonObject, headers: response.allHeaderFields)
                                    return Single.just(response)
                                } catch {
                                    return Single.error(error)
                                }
                             }
                             .do(onError: { error in
                                DDLogError("AuthorizeUploadSyncAction: can't authorize upload - \(error)")
                                DDLogError("AuthorizeUploadSyncAction: key=\(self.key);oldMd5=\(self.oldMd5 ?? "nil");md5=\(self.md5);filesize=\(self.filesize);mtime=\(self.mtime)")
                             })
    }
}
