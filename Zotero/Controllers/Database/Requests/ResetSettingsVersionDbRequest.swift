//
//  ResetSettingsVersionDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 06.04.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ResetSettingsVersionDbRequest: DbRequest {
    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        let libraries = database.objects(RCustomLibrary.self)
        for library in libraries {
            library.versions?.settings = 0
        }

        let groups = database.objects(RGroup.self)
        for group in groups {
            group.versions?.settings = 0
        }
    }
}
