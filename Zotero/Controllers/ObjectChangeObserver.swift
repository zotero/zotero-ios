//
//  ObjectChangeObserver.swift
//  Zotero
//
//  Created by Michal Rentka on 13/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjack
import RxSwift
import RealmSwift

protocol ObjectChangeObserver: class {
    var observable: PublishSubject<[LibraryIdentifier]> { get }
}

final class RealmObjectChangeObserver: ObjectChangeObserver {
    let observable: PublishSubject<[LibraryIdentifier]>
    private let dbStorage: DbStorage

    private var collectionsToken: NotificationToken?
    private var itemsToken: NotificationToken?
    private var searchesToken: NotificationToken?

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
        } catch let error {
            DDLogError("RealmObjectChangeObserver: can't load objects to observe - \(error)")
        }
    }

    private func registerObserver<Obj: UpdatableObject&Syncable>(for: Obj.Type,
                                                                 coordinator: DbCoordinator) throws -> NotificationToken {
        let objects = try coordinator.perform(request: ReadUserChangedObjectsDbRequest<Obj>())
        return objects.observe({ [weak self] changes in
            switch changes {
            case .update(let results, _, let insertions, let modifications):
                let updated = (insertions + modifications).map({ results[$0] })
                self?.reportChangedLibraries(for: updated)
            case .initial: break // we ignore the initial change, initially we perform a full sync anyway
            case .error(let error):
                DDLogError("RealmObjectChangeObserver: \(Obj.self) observing error - \(error)")
            }
        })
    }

    private func reportChangedLibraries(for objects: [Syncable]) {
        let libraryIds = Array(Set(objects.compactMap({ $0.libraryObject?.identifier })))
        guard !libraryIds.isEmpty else { return }
        self.observable.on(.next(libraryIds))
    }
}
