//
//  UpdateVersionsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 08/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

enum UpdateVersionType {
    case object(SyncController.Object)
    case settings
}

struct UpdateVersionsDbRequest: DbRequest {
    let version: Int
    let libraryId: LibraryIdentifier
    let type: UpdateVersionType

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        switch self.libraryId {
        case .custom(let type):
            guard let library = database.object(ofType: RCustomLibrary.self, forPrimaryKey: type.rawValue) else {
                throw DbError.objectNotFound
            }

            let versions: RVersions = library.versions ?? RVersions()
            if library.versions == nil {
                database.add(versions)
                library.versions = versions
            }

            try self.update(versions: versions, type: self.type, version: self.version)

        case .group(let identifier):
            guard let library = database.object(ofType: RGroup.self, forPrimaryKey: identifier) else {
                throw DbError.objectNotFound
            }

            let versions: RVersions = library.versions ?? RVersions()
            if library.versions == nil {
                database.add(versions)
                library.versions = versions
            }

            try self.update(versions: versions, type: self.type, version: self.version)
        }
    }

    private func update(versions: RVersions, type: UpdateVersionType, version: Int) throws {
        switch type {
        case .settings:
            versions.settings = version
        case .object(let object):
            switch object {
            case .group:
                throw DbError.objectNotFound
            case .collection:
                versions.collections = version
            case .item:
                versions.items = version
            case .trash:
                versions.trash = version
            case .search:
                versions.searches = version
            case .tag: break
            }
        }
    }
}
