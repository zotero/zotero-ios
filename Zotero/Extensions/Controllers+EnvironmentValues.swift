//
//  Controllers+EnvironmentValues.swift
//  Zotero
//
//  Created by Michal Rentka on 16/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

import CocoaLumberjackSwift
import RealmSwift

struct DbStorageEnvironmentKey: EnvironmentKey {
    static var defaultValue: DbStorage {
        return RealmDbStorage(config: .defaultConfiguration)
    }
}

struct ApiClientEnvironmentKey: EnvironmentKey {
    static var defaultValue: ApiClient {
        return ZoteroApiClient(baseUrl: ApiConstants.baseUrlString, configuration: URLSessionConfiguration.default)
    }
}

struct FileStorageEnvironmentKey: EnvironmentKey {
    static var defaultValue: FileStorage {
        return FileStorageController()
    }
}

struct SchemaControllerEnvironmentKey: EnvironmentKey {
    static var defaultValue: SchemaController {
        return SchemaController()
    }
}

struct SecureStorageEnvironmentKey: EnvironmentKey {
    static var defaultValue: SecureStorage {
        return KeychainSecureStorage()
    }
}

struct SessionControllerEnvironmentKey: EnvironmentKey {
    static var defaultValue: SessionController {
        return SessionController(secureStorage: KeychainSecureStorage())
    }
}

extension EnvironmentValues {
    var dbStorage: DbStorage {
        get { self[DbStorageEnvironmentKey.self] }
        set { self[DbStorageEnvironmentKey.self] = newValue }
    }

    var apiClient: ApiClient {
        get { self[ApiClientEnvironmentKey.self] }
        set { self[ApiClientEnvironmentKey.self] = newValue }
    }

    var fileStorage: FileStorage {
        get { self[FileStorageEnvironmentKey.self] }
        set { self[FileStorageEnvironmentKey.self] = newValue }
    }

    var schemaController: SchemaController {
        get { self[SchemaControllerEnvironmentKey.self] }
        set { self[SchemaControllerEnvironmentKey.self] = newValue }
    }

    var secureStorage: SecureStorage {
        get { self[SecureStorageEnvironmentKey.self] }
        set { self[SecureStorageEnvironmentKey.self] = newValue }
    }

    var sessionController: SessionController {
        get { self[SessionControllerEnvironmentKey.self] }
        set { self[SessionControllerEnvironmentKey.self] = newValue }
    }
}
