//
//  Controllers.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

class Controllers {
    let apiClient: ApiClient
    let secureStorage: SecureStorage
    let dbStorage: DbStorage

    init(apiClient: ApiClient, secureStorage: SecureStorage, dbStorage: DbStorage) {
        self.apiClient = apiClient
        self.secureStorage = secureStorage
        self.dbStorage = dbStorage
    }
}
