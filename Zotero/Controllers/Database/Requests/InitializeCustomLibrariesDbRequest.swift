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
        let libraryData = try database.autocreatedObject(ofType: RCustomLibrary.self,
                                                         forPrimaryKey: RCustomLibraryType.myLibrary.rawValue)

        if libraryData.0 {
            libraryData.1.orderId = 1
            let versions = RVersions()
            database.add(versions)
            libraryData.1.versions = versions
        }
    }
}
