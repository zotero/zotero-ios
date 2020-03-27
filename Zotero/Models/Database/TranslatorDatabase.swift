//
//  TranslatorDatabase.swift
//  Zotero
//
//  Created by Michal Rentka on 27/03/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct TranslatorDatabase {
    private static let schemaVersion: UInt64 = 0

    static var configuration: Realm.Configuration {
        return Realm.Configuration(fileURL: Files.translatorsDbFile.createUrl(),
                                   schemaVersion: schemaVersion,
                                   migrationBlock: { _, _ in
            // TODO: Implement when needed
        })
    }
}
