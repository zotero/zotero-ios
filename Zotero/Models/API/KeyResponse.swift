//
//  KeyResponse.swift
//  Zotero
//
//  Created by Michal Rentka on 24/06/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct KeyResponse {
    let username: String
    let displayName: String
    let user: AccessPermissions.Permissions
    let defaultGroup: AccessPermissions.Permissions?
    let groups: [Int: AccessPermissions.Permissions]

    init(response: Any) throws {
        guard let data = response as? [String: Any] else { throw Parsing.Error.notDictionary }

        let accessData: [String: Any] = try data.apiGet(key: "access")

        self.username = (data["username"] as? String) ?? ""
        self.displayName = (data["displayName"] as? String) ?? ""

        let libraryData = accessData["user"] as? [String: Any]
        self.user = AccessPermissions.Permissions(data: libraryData)

        let groupData = accessData["groups"] as? [String: [String: Any]]
        if let data = groupData {
            var defaultGroup: AccessPermissions.Permissions?
            var groups: [Int: AccessPermissions.Permissions] = [:]

            data.forEach { groupData in
                if groupData.key == "all" {
                    defaultGroup = AccessPermissions.Permissions(data: groupData.value)
                } else if let intKey = Int(groupData.key) {
                    groups[intKey] = AccessPermissions.Permissions(data: groupData.value)
                }
            }

            self.defaultGroup = defaultGroup
            self.groups = groups
        } else {
            self.defaultGroup = nil
            self.groups = [:]
        }
    }

    // MARK: - Testing only

    init() {
        self.user = AccessPermissions.Permissions(data: nil)
        self.defaultGroup = AccessPermissions.Permissions(data: nil)
        self.groups = [:]
        self.username = ""
        self.displayName = ""
    }
}
