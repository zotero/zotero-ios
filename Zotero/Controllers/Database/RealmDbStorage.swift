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
    fileprivate let config: Realm.Configuration

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

    fileprivate func performInAutoreleasepoolIfNeeded<Result>(invoking body: () throws -> Result) rethrows -> Result {
        if Thread.isMainThread {
            return try body()
        }
        return try autoreleasepool {
            return try body()
        }
    }
}

extension RealmDbStorage: DbStorage {
    func perform(with coordinatorAction: (DbCoordinator) throws -> Void) throws {
        try self.perform(with: coordinatorAction, invalidateRealm: false)
    }

    func perform(with coordinatorAction: (DbCoordinator) throws -> Void, invalidateRealm: Bool) throws {
        try self.performInAutoreleasepoolIfNeeded {
            let realm = try Realm(configuration: self.config)
            let coordinator = RealmDbCoordinator(realm: realm)

            try coordinatorAction(coordinator)

            guard invalidateRealm else { return }

            realm.invalidate()
        }
    }

    func perform<Request>(request: Request) throws -> Request.Response where Request : DbResponseRequest {
        return try self.perform(request: request, invalidateRealm: false)
    }

    func perform<Request>(request: Request, invalidateRealm: Bool) throws -> Request.Response where Request : DbResponseRequest {
        return try self.performInAutoreleasepoolIfNeeded {
            let realm = try Realm(configuration: self.config)

            defer {
                if invalidateRealm {
                    realm.invalidate()
                }
            }

            let coordinator = RealmDbCoordinator(realm: realm)
            return try coordinator.perform(request: request)
        }
    }

    func perform(request: DbRequest) throws {
        try self.performInAutoreleasepoolIfNeeded {
            let realm = try Realm(configuration: self.config)
            let coordinator = RealmDbCoordinator(realm: realm)
            try coordinator.perform(request: request)
            realm.invalidate()
        }
    }

    func perform(writeRequests requests: [DbRequest]) throws {
        try self.performInAutoreleasepoolIfNeeded {
            let realm = try Realm(configuration: self.config)
            let coordinator = RealmDbCoordinator(realm: realm)
            try coordinator.perform(writeRequests: requests)
            realm.invalidate()
        }
    }
}

struct RealmDbCoordinator {
    private let realm: Realm

    init(realm: Realm) {
        self.realm = realm
    }
}

extension RealmDbCoordinator: DbCoordinator {
    func perform(request: DbRequest) throws  {
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

    func perform<Request>(request: Request) throws -> Request.Response where Request : DbResponseRequest {
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

    func perform(writeRequests requests: [DbRequest]) throws {
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

    func invalidate() {
        self.realm.invalidate()
    }
}
