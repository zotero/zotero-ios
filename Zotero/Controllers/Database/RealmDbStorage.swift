//
//  RealmDbController.swift
//  Zotero
//
//  Created by Michal Rentka on 04/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

enum RealmDbError: Error {
    case autocreateMissingPrimaryKey
}

class RealmDbStorage {
    private static let schemaVersion: UInt64 = 1
    private let config: Realm.Configuration

    init(config: Realm.Configuration) {
        self.config = config
    }

    convenience init(url: URL) {
        var config = Realm.Configuration(fileURL: url,
                                         schemaVersion: RealmDbStorage.schemaVersion,
                                         migrationBlock: { _, _ in
            // TODO: Implement when needed
        })
        config.deleteRealmIfMigrationNeeded = true
        self.init(config: config)
    }
}

extension RealmDbStorage: DbStorage {
    func createCoordinator() throws -> DbCoordinator {
        return try RealmDbCoordinator(config: self.config)
    }
}

class RealmDbCoordinator {
    private let realm: Realm

    init(config: Realm.Configuration) throws {
        self.realm = try Realm(configuration: config)
    }
}

extension RealmDbCoordinator: DbCoordinator {
    func perform<Request>(request: Request) throws where Request : DbRequest {
        self.realm.beginWrite()
        do {
            try request.process(in: self.realm)
            try self.realm.commitWrite()
        } catch let error {
            throw error
        }
    }

    func perform<Request>(request: Request) -> Request.Response where Request : DbResponseRequest {
        return request.process(in: self.realm)
    }
}

extension Realm {
    func autocreatedObject<Element: Object, KeyType>(ofType type: Element.Type,
                                                     forPrimaryKey key: KeyType) throws -> Element {
        if let existing = self.object(ofType: type, forPrimaryKey: key) {
            return existing
        }

        guard let primaryKey = type.primaryKey() else {
            throw RealmDbError.autocreateMissingPrimaryKey
        }

        let object = type.init()
        object.setValue(key, forKey: primaryKey)
        self.add(object)
        return object
    }
}
