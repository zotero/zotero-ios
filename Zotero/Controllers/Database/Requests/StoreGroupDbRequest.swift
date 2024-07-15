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

        let isOwner = (response.data.owner == userId)
        let canEditMetadata: Bool
        let canEditFiles: Bool

        if response.data.libraryEditing == "admins" {
            canEditMetadata = isOwner || (response.data.admins ?? []).contains(userId)
        } else {
            canEditMetadata = true
        }

        switch response.data.fileEditing {
        case "none":
            canEditFiles = false

        case "admins":
            canEditFiles = isOwner || (response.data.admins ?? []).contains(userId)

        case "members":
            canEditFiles = true

        default:
            canEditFiles = isOwner
        }

        group.name = response.data.name
        group.desc = response.data.description
        group.owner = response.data.owner
        group.type = groupType
        group.canEditMetadata = canEditMetadata
        group.canEditFiles = canEditFiles
        group.version = response.version
        group.syncState = .synced
        group.isLocalOnly = false
    }
}
