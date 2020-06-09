//
//  AccessPermissions.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct AccessPermissions {
    struct Permissions {
        let library: Bool
        let notes: Bool
        let files: Bool
        let write: Bool
    }

    let user: Permissions
    let groupDefault: Permissions?
    let groups: [Int: Permissions]
}

extension AccessPermissions.Permissions {
    init(data: [String: Any]?) {
        self.library = (data?["library"] as? Bool) ?? false
        let write = (data?["write"] as? Bool) ?? false
        self.write = write
        self.notes = (data?["notes"] as? Bool) ?? write
        self.files = (data?["files"] as? Bool) ?? write
    }
}
