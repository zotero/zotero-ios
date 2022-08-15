//
//  StoreGroupDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 05/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct StoreGroupDbRequest: DbRequest {
    enum Error: Swift.Error {
        case unknownGroupType
    }

    let response: GroupResponse
    let userId: Int

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        guard let groupType = GroupType(rawValue: self.response.data.type) else {
            throw Error.unknownGroupType
        }

        let group: RGroup

        if let _group = database.object(ofType: RGroup.self, forPrimaryKey: self.response.identifier) {
            group = _group
        } else {
            group = RGroup()
            group.identifier = self.response.identifier
            group.versions = RVersions()
            database.add(group)
        }

        let canEditMetadata: Bool
        let canEditFiles: Bool

        if self.userId == self.response.data.owner {
            canEditMetadata = true
            canEditFiles = true
        } else {
            if self.response.data.libraryEditing == "admins" {
                canEditMetadata = (self.response.data.admins ?? []).contains(self.userId)
            } else {
                canEditMetadata = true
            }

            switch self.response.data.fileEditing {
            case "none":
                canEditFiles = false
            case "admins":
                canEditFiles = (self.response.data.admins ?? []).contains(self.userId)
            case "members":
                canEditFiles = true
            default:
                canEditFiles = false
            }
        }

        group.name = self.response.data.name
        group.desc = self.response.data.description
        group.owner = self.response.data.owner
        group.type = groupType
        group.canEditMetadata = canEditMetadata
        group.canEditFiles = canEditFiles
        group.version = self.response.version
        group.syncState = .synced
        group.isLocalOnly = false
    }
}
