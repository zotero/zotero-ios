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
    case object(SyncObject)
    case deletions
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

            if let versions = library.versions {
                try self.update(versions: versions, type: self.type, version: self.version)
            }

        case .group(let identifier):
            guard let library = database.object(ofType: RGroup.self, forPrimaryKey: identifier) else {
                throw DbError.objectNotFound
            }


            if let versions = library.versions {
                try self.update(versions: versions, type: self.type, version: self.version)
            }
        }
    }

    private func update(versions: RVersions, type: UpdateVersionType, version: Int) throws {
        switch type {
        case .deletions:
            versions.deletions = version
        case .object(let object):
            switch object {
            case .collection:
                versions.collections = version
            case .item:
                versions.items = version
            case .trash:
                versions.trash = version
            case .search:
                versions.searches = version
            case .settings:
                versions.settings = version
            }
        }
    }
}
