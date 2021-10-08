//
//  TestControllers.swift
//  ZoteroTests
//
//  Created by Michal Rentka on 08.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

@testable import Zotero

import Foundation

final class TestControllers {
    static let apiClient: ApiClient = ZoteroApiClient(baseUrl: ApiConstants.baseUrlString, configuration: .default)
    static let fileStorage: FileStorage = FileStorageController()
    static let schemaController: SchemaController = SchemaController()
    static let secureStorage: SecureStorage = KeychainSecureStorage()
    static let dateParser = DateParser()
}
