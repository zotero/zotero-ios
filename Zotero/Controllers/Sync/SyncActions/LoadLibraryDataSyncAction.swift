//
//  LoadLibraryDataSyncAction.swift
//  Zotero
//
//  Created by Michal Rentka on 30/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RxSwift

struct LoadLibraryDataSyncAction: SyncAction {
    typealias Result = [LibraryData]

    let type: SyncController.Libraries
    let fetchUpdates: Bool
    let loadVersions: Bool
    let webDavEnabled: Bool

    unowned let dbStorage: DbStorage
    let queue: DispatchQueue

    var result: Single<[LibraryData]> {
        return Single.create { subscriber -> Disposable in
            let request: ReadLibrariesDataDbRequest

            switch self.type {
            case .all:
                request = ReadLibrariesDataDbRequest(identifiers: nil, fetchUpdates: self.fetchUpdates, loadVersions: self.loadVersions, webDavEnabled: self.webDavEnabled)

            case .specific(let ids):
                if ids.isEmpty {
                    subscriber(.success([]))
                    return Disposables.create()
                }
                request = ReadLibrariesDataDbRequest(identifiers: ids, fetchUpdates: self.fetchUpdates, loadVersions: self.loadVersions, webDavEnabled: self.webDavEnabled)
            }

            do {
                let data = try self.dbStorage.perform(request: request, on: self.queue, invalidateRealm: true)
                subscriber(.success(data))
            } catch let error {
                subscriber(.failure(error))
            }

            return Disposables.create()
        }
    }
}
