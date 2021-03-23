//
//  RealmDbController.swift
//  Zotero
//
//  Created by Michal Rentka on 04/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RealmSwift

enum RealmDbError: Error {
    case autocreateMissingPrimaryKey
}

final class RealmDbStorage {
    private let config: Realm.Configuration

    init(config: Realm.Configuration) {
        self.config = config
    }

    var willPerformBetaWipe: Bool {
        return self.config.deleteRealmIfMigrationNeeded
    }

    func clear() {
        guard let realmUrl = self.config.fileURL else { return }

        let realmUrls = [realmUrl,
                         realmUrl.appendingPathExtension("lock"),
                         realmUrl.appendingPathExtension("note"),
                         realmUrl.appendingPathExtension("management")]

        for url in realmUrls {
            do {
                try FileManager.default.removeItem(at: url)
            } catch let error {
                DDLogError("RealmDbStorage: couldn't delete file at '\(url.absoluteString)' - \(error)")
            }
        }
    }
}

extension RealmDbStorage: DbStorage {
    func createCoordinator() throws -> DbCoordinator {
        return try RealmDbCoordinator(config: self.config)
    }
}

struct RealmDbCoordinator {
    private let realm: Realm

    init(config: Realm.Configuration) throws {
        self.realm = try Realm(configuration: config)
    }
}

extension RealmDbCoordinator: DbCoordinator {
    func perform(request: DbRequest) throws  {
        try self.performInAutoreleasepoolIfNeeded {
            if !request.needsWrite {
                try request.process(in: self.realm)
                return
            }

            if self.realm.isInWriteTransaction {
                DDLogError("RealmDbCoordinator: realm already writing \(type(of: request))")
                try request.process(in: self.realm)
                return
            }

            try self.realm.write(withoutNotifying: request.ignoreNotificationTokens ?? []) {
                try request.process(in: self.realm)
            }
        }
    }

    func perform<Request>(request: Request) throws -> Request.Response where Request : DbResponseRequest {
        return try self.performInAutoreleasepoolIfNeeded {
            if !request.needsWrite {
                return try request.process(in: self.realm)
            }

            if self.realm.isInWriteTransaction {
                DDLogError("RealmDbCoordinator: realm already writing \(type(of: request))")
                return try request.process(in: self.realm)
            }

            return try self.realm.write(withoutNotifying: request.ignoreNotificationTokens ?? []) {
                return try request.process(in: self.realm)
            }
        }
    }

    /// Writes multiple requests in single write transaction.
    func perform(requests: [DbRequest]) throws {
        try self.performInAutoreleasepoolIfNeeded {

            if self.realm.isInWriteTransaction {
                DDLogError("RealmDbCoordinator: realm already writing")
                for request in requests {
                    guard request.needsWrite else { continue }
                    DDLogError("\(type(of: request))")
                    try request.process(in: self.realm)
                }
                return
            }

            try self.realm.write {
                for request in requests {
                    guard request.needsWrite else { continue }
                    try request.process(in: self.realm)
                }
            }
        }
    }

    private func performInAutoreleasepoolIfNeeded<Result>(invoking body: () throws -> Result) rethrows -> Result {
        if Thread.isMainThread {
            return try body()
        }
        return try autoreleasepool {
            return try body()
        }
    }
}

extension Realm {
    /// Tries to find a library object with LibraryIdentifier, if it doesn't exist it creates a new object
    /// - parameter key: Identifier for given library object
    /// - returns: Tuple, Bool indicates whether the object had to be created and LibraryObject is the existing/new object
    func autocreatedLibraryObject(forPrimaryKey key: LibraryIdentifier) throws -> (Bool, LibraryObject) {
        switch key {
        case .custom(let type):
            let (isNew, object) = try self.autocreatedObject(ofType: RCustomLibrary.self, forPrimaryKey: type.rawValue)
            return (isNew, .custom(object))

        case .group(let identifier):
            let (isNew, object) = try self.autocreatedObject(ofType: RGroup.self, forPrimaryKey: identifier)
            return (isNew, .group(object))
        }
    }

    /// Tries to find an object with primary key, if it doesn't exist it creates a new object
    /// - parameter type: Type of object to return
    /// - parameter key: Primary key of object
    /// - returns: Tuple, Bool indicates whether the object had to be created and Element is the existing/new object
    func autocreatedObject<Element: Object, KeyType>(ofType type: Element.Type,
                                                     forPrimaryKey key: KeyType) throws -> (Bool, Element) {
        if let existing = self.object(ofType: type, forPrimaryKey: key) {
            return (false, existing)
        }

        guard let primaryKey = type.primaryKey() else {
            throw RealmDbError.autocreateMissingPrimaryKey
        }

        let object = type.init()
        object.setValue(key, forKey: primaryKey)
        self.add(object)
        return (true, object)
    }
}
