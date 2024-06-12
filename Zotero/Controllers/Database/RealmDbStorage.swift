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
        FileManager.default.clearDatabaseFiles(at: realmUrl)
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
    func perform(on queue: DispatchQueue, with coordinatorAction: (DbCoordinator) throws -> Void) throws {
        try self.performInAutoreleasepoolIfNeeded {
            let coordinator = try RealmDbCoordinator(configuration: self.config, queue: queue)
            try coordinatorAction(coordinator)
        }
    }

    func perform<Request>(request: Request, on queue: DispatchQueue) throws -> Request.Response where Request: DbResponseRequest {
        return try self.perform(request: request, on: queue, invalidateRealm: false, refreshRealm: false)
    }

    func perform<Request>(request: Request, on queue: DispatchQueue, refreshRealm: Bool) throws -> Request.Response where Request: DbResponseRequest {
        return try self.perform(request: request, on: queue, invalidateRealm: false, refreshRealm: refreshRealm)
    }

    func perform<Request>(request: Request, on queue: DispatchQueue, invalidateRealm: Bool) throws -> Request.Response where Request: DbResponseRequest {
        return try self.perform(request: request, on: queue, invalidateRealm: invalidateRealm, refreshRealm: false)
    }

    func perform<Request>(request: Request, on queue: DispatchQueue, invalidateRealm: Bool, refreshRealm: Bool) throws -> Request.Response where Request: DbResponseRequest {
        return try self.performInAutoreleasepoolIfNeeded {
            let coordinator = try RealmDbCoordinator(configuration: self.config, queue: queue)
            if refreshRealm {
                coordinator.refresh()
            }
            let result = try coordinator.perform(request: request)

            if invalidateRealm {
                coordinator.invalidate()
            }

            return result
        }
    }

    func perform(request: DbRequest, on queue: DispatchQueue) throws {
        try self.performInAutoreleasepoolIfNeeded {
            let coordinator = try RealmDbCoordinator(configuration: self.config, queue: queue)
            try coordinator.perform(request: request)
            // Since there is no result we can always invalidate realm to free memory
            coordinator.invalidate()
        }
    }

    func perform(writeRequests requests: [DbRequest], on queue: DispatchQueue) throws {
        try self.performInAutoreleasepoolIfNeeded {
            let coordinator = try RealmDbCoordinator(configuration: self.config, queue: queue)
            try coordinator.perform(writeRequests: requests)
            // Since there is no result we can always invalidate realm to free memory
            coordinator.invalidate()
        }
    }
}

struct RealmDbCoordinator {
    private let realm: Realm

    init(configuration: Realm.Configuration, queue: DispatchQueue) throws {
        dispatchPrecondition(condition: .onQueue(queue))
        self.realm = try Realm(configuration: configuration, queue: queue)
    }
}

extension RealmDbCoordinator: DbCoordinator {
    func perform(request: DbRequest) throws {
        if !request.needsWrite {
            try request.process(in: self.realm)
            return
        }

        if self.realm.isInWriteTransaction {
            DDLogError("RealmDbCoordinator: realm already writing \(type(of: request))")
            try request.process(in: self.realm)
            return
        }

        try self.realm.write {
            try request.process(in: self.realm)
        }
    }

    func perform<Request>(request: Request) throws -> Request.Response where Request: DbResponseRequest {
        if !request.needsWrite {
            return try request.process(in: self.realm)
        }

        if self.realm.isInWriteTransaction {
            DDLogError("RealmDbCoordinator: realm already writing \(type(of: request))")
            return try request.process(in: self.realm)
        }

        return try self.realm.write {
            return try request.process(in: self.realm)
        }
    }

    func perform(writeRequests requests: [DbRequest]) throws {
        if Thread.isMainThread {
            DDLogWarn("!!! RealmDbStorage: writing on main thread")
        }

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

    fileprivate func refresh() {
        self.realm.refresh()
    }

    func invalidate() {
        guard !Thread.isMainThread else {
            DDLogWarn("!!! RealmDbStorage: invalidating on main thread")
            return
        }
        self.realm.invalidate()
    }
}

extension Results where Element: Syncable & Object {
    func uniqueObject(key: String, libraryId: LibraryIdentifier) -> Element? {
        let filtered = filter(.key(key, in: libraryId))

        if filtered.isEmpty {
            return nil
        }

        if filtered.count == 1 {
            return filtered.first
        }

        DDLogError("\(type(of: Element.self)) \(key); \(libraryId) contains more than 1 instance!")

        let sorted = filtered.sorted(byKeyPath: "version", ascending: false)

        if let database = realm, database.isInWriteTransaction {
            for idx in (1..<sorted.count).reversed() {
                database.delete(sorted[idx])
            }
        }

        return sorted.first
    }
}
