//
//  SyncSettingsState.swift
//  Zotero
//
//  Created by Michal Rentka on 06.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RxSwift

struct SyncSettingsState: ViewModelState {
    enum FileSyncType: Hashable {
        case zotero
        case webDav
    }

    let account: String

    var fileSyncType: FileSyncType
    var updatingFileSyncType: Bool
    var scheme: WebDavScheme
    var url: String
    var username: String
    var password: String
    var isVerifyingWebDav: Bool
    var webDavVerificationResult: Result<(), Error>?
    var apiDisposeBag: DisposeBag
    var libraries: [Library]

    init(account: String, fileSyncType: FileSyncType, scheme: WebDavScheme, url: String, username: String, password: String, isVerified: Bool) {
        self.account = account
        self.fileSyncType = fileSyncType
        updatingFileSyncType = false
        self.scheme = scheme
        self.url = url
        self.username = username
        self.password = password
        isVerifyingWebDav = false
        webDavVerificationResult = isVerified ? .success(()) : nil
        apiDisposeBag = DisposeBag()
        libraries = []
    }

    func cleanup() {}
}
