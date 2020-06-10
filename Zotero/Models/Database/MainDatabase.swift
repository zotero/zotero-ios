//
//  MainDatabase.swift
//  Zotero
//
//  Created by Michal Rentka on 27/03/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct MainDatabase {
    private static let schemaVersion: UInt64 = 13

    static func configuration(url: URL) -> Realm.Configuration {
        return Realm.Configuration(fileURL: url,
                                   schemaVersion: schemaVersion,
                                   migrationBlock: { _, _ in
            // TODO: Implement when needed
        })
    }
}
