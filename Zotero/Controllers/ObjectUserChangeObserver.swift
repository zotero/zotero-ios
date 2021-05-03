//
//  ObjectUserChangeObserver.swift
//  Zotero
//
//  Created by Michal Rentka on 13/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxSwift
import RealmSwift

protocol ObjectUserChangeObserver: AnyObject {
    var observable: PublishSubject<[LibraryIdentifier]> { get }
}

final class RealmObjectUserChangeObserver: ObjectUserChangeObserver {
    let observable: PublishSubject<[LibraryIdentifier]>
    private let dbStorage: DbStorage

    private var collectionsToken: NotificationToken?
    private var itemsToken: NotificationToken?
    private var searchesToken: NotificationToken?
    private var pagesToken: NotificationToken?

    init(dbStorage: DbStorage) {
        self.dbStorage = dbStorage
        self.observable = PublishSubject()
        self.setupObserving()
    }

    private func setupObserving() {
        do {
            let coordinator = try self.dbStorage.createCoordinator()
            self.collectionsToken = try self.registerObserver(for: RCollection.self, coordinator: coordinator)
            self.itemsToken = try self.registerObserver(for: RItem.self, coordinator: coordinator)
            self.searchesToken = try self.registerObserver(for: RSearch.self, coordinator: coordinator)
            self.pagesToken = try self.registerSettingsObserver(coordinator: coordinator)
        } catch let error {
            DDLogError("RealmObjectChangeObserver: can't load objects to observe - \(error)")
        }
    }

    private func registerSettingsObserver(coordinator: DbCoordinator) throws -> NotificationToken {
        let objects = try coordinator.perform(request: ReadUserChangedObjectsDbRequest<RPageIndex>())
        return objects.observe({ [weak self] changes in
            switch changes {
            case .update(_, _, let insertions, let modifications):
                guard !insertions.isEmpty || !modifications.isEmpty else { return }
                // Settings are always reported by user library, even if they belong to groups.
                self?.observable.on(.next([.custom(.myLibrary)]))
            case .initial: break // ignore the initial change, initially a full sync is performed anyway
            case .error(let error):
                DDLogError("RealmObjectChangeObserver: RPageIndex observing error - \(error)")
            }
        })
    }

    private func registerObserver<Obj: UpdatableObject&Syncable>(for: Obj.Type, coordinator: DbCoordinator) throws -> NotificationToken {
        let objects = try coordinator.perform(request: ReadUserChangedObjectsDbRequest<Obj>())
        return objects.observe({ [weak self] changes in
            switch changes {
            case .update(let results, let deletions, let insertions, let modifications):
                let correctedModifications = Database.correctedModifications(from: modifications, insertions: insertions, deletions: deletions)
                let updated = (insertions + correctedModifications).map({ results[$0] })
                self?.reportChangedLibraries(for: updated)
            case .initial: break // ignore the initial change, initially a full sync is performed anyway
            case .error(let error):
                DDLogError("RealmObjectChangeObserver: \(Obj.self) observing error - \(error)")
            }
        })
    }

    private func reportChangedLibraries(for objects: [Syncable]) {
        let libraryIds = Array(Set(objects.compactMap({ $0.libraryId })))
        guard !libraryIds.isEmpty else { return }
        self.observable.on(.next(libraryIds))
    }
}
