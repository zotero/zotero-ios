//
//  InitializeCustomLibrariesDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 05/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct InitializeCustomLibrariesDbRequest: DbRequest {

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        let (isNew, object) = try database.autocreatedObject(ofType: RCustomLibrary.self,
                                                             forPrimaryKey: RCustomLibraryType.myLibrary.rawValue)

        if isNew {
            object.orderId = 1
            let versions = RVersions()
            database.add(versions)
            object.versions = versions
        }
    }
}
