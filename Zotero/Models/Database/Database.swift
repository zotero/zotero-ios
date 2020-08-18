//
//  Database.swift
//  Zotero
//
//  Created by Michal Rentka on 27/03/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct Database {
    private static let schemaVersion: UInt64 = 15
    private static let migrationBlock: MigrationBlock = createMigrationBlock()

    static func mainConfiguration(url: URL) -> Realm.Configuration {
        return Realm.Configuration(fileURL: url,
                                   schemaVersion: schemaVersion,
                                   migrationBlock: migrationBlock)
    }

    static var translatorConfiguration: Realm.Configuration {
        return Realm.Configuration(fileURL: Files.translatorsDbFile.createUrl(),
                                   schemaVersion: schemaVersion,
                                   migrationBlock: migrationBlock)
    }

    private static func createMigrationBlock() -> MigrationBlock {
        return { _, _ in
            // TODO: Implement when needed
        }
    }
}
