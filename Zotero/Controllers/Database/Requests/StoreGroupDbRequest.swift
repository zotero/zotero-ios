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
    let response: GroupResponse
    let userId: Int

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws {
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
        group.rawType = self.response.data.type
        group.canEditMetadata = canEditMetadata
        group.canEditFiles = canEditFiles
        group.version = self.response.version
        group.syncState = .synced
        group.isLocalOnly = false
    }
}
