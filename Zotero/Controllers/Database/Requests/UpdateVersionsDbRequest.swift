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
    let libraryId: Int
    let type: UpdateVersionType

    var needsWrite: Bool { return true }

    init(version: Int, library: SyncController.Library, type: UpdateVersionType) {
        self.version = version
        self.type = type
        switch library {
        case .group(let groupId):
            self.libraryId = groupId
        case .user:
            self.libraryId = RLibrary.myLibraryId
        }
    }

    func process(in database: Realm) throws {
        guard let library = database.object(ofType: RLibrary.self, forPrimaryKey: self.libraryId) else {
            throw DbError.objectNotFound
        }

        let versions: RVersions = library.versions ?? RVersions()
        if library.versions == nil {
            database.add(versions)
            library.versions = versions
        }

        switch self.type {
        case .settings:
            versions.settings = self.version
        case .object(let object):
            switch object {
            case .group:
                throw DbError.objectNotFound
            case .collection:
                versions.collections = self.version
            case .item:
                versions.items = self.version
            case .trash:
                versions.trash = self.version
            case .search:
                versions.searches = self.version
            case .tag: break
            }
        }
    }
}
