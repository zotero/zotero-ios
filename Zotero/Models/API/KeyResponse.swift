//
//  KeyResponse.swift
//  Zotero
//
//  Created by Michal Rentka on 24/06/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum KeyResponseError: Error {
    case accessDataMissing
}

struct KeyResponse {
    let username: String
    let user: SyncController.AccessPermissions.Permissions
    let defaultGroup: SyncController.AccessPermissions.Permissions
    let groups: [Int: SyncController.AccessPermissions.Permissions]

    init(response: Any) throws {
        guard let data = response as? [String: Any],
              let accessData = data["access"] as? [String: Any] else { throw KeyResponseError.accessDataMissing }

        self.username = (data["username"] as? String) ?? ""

        let libraryData = accessData["user"] as? [String: Any]
        self.user = SyncController.AccessPermissions.Permissions(data: libraryData)

        let groupData = accessData["groups"] as? [String: [String: Any]]
        if let data = groupData {
            var defaultGroup: SyncController.AccessPermissions.Permissions?
            var groups: [Int: SyncController.AccessPermissions.Permissions] = [:]

            data.forEach { groupData in
                if groupData.key == "all" {
                    defaultGroup = SyncController.AccessPermissions.Permissions(data: groupData.value)
                } else if let intKey = Int(groupData.key) {
                    groups[intKey] = SyncController.AccessPermissions.Permissions(data: groupData.value)
                }
            }

            self.defaultGroup = defaultGroup ?? SyncController.AccessPermissions.Permissions(data: nil)
            self.groups = groups
        } else {
            self.defaultGroup = SyncController.AccessPermissions.Permissions(data: nil)
            self.groups = [:]
        }
    }

    // MARK: - Testing only

    init() {
        self.user = SyncController.AccessPermissions.Permissions(data: nil)
        self.defaultGroup = SyncController.AccessPermissions.Permissions(data: nil)
        self.groups = [:]
        self.username = ""
    }
}

extension SyncController.AccessPermissions.Permissions {
    init(data: [String: Any]?) {
        self.library = (data?["library"] as? Bool) ?? false
        self.write = (data?["write"] as? Bool) ?? false
        self.notes = (data?["notes"] as? Bool) ?? false
        self.files = (data?["files"] as? Bool) ?? false
    }
}
