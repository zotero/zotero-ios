//
//  SyncSettingsState.swift
//  Zotero
//
//  Created by Michal Rentka on 06.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct SyncSettingsState: ViewModelState {
    enum FileSyncType: Hashable {
        case zotero
        case webDav
    }

    let account: String

    var fileSyncType: FileSyncType
    var scheme: WebDavScheme
    var url: String
    var username: String
    var password: String
    var error: WebDavController.Error?

    init(account: String, fileSyncType: FileSyncType, scheme: WebDavScheme, url: String, username: String, password: String) {
        self.account = account
        self.fileSyncType = fileSyncType
        self.scheme = scheme
        self.url = url
        self.username = username
        self.password = password
    }

    func cleanup() {}
}
