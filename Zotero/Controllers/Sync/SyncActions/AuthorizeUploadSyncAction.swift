//
//  AuthorizeUploadSyncAction.swift
//  Zotero
//
//  Created by Michal Rentka on 30/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

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

    unowned let apiClient: ApiClient

    var result: Single<AuthorizeUploadResponse> {
        let request = AuthorizeUploadRequest(libraryId: self.libraryId, userId: self.userId, key: self.key, filename: self.filename,
                                             filesize: self.filesize, md5: self.md5, mtime: self.mtime)
        return self.apiClient.send(request: request).flatMap { (data, _) -> Single<AuthorizeUploadResponse> in
           do {
               let jsonObject = try JSONSerialization.jsonObject(with: data, options: .allowFragments)
               let response = try AuthorizeUploadResponse(from: jsonObject)
               return Single.just(response)
           } catch {
               return Single.error(error)
           }
        }
    }
}
