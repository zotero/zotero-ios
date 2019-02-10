//
//  InitializeMyLibraryDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 05/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct InitializeMyLibraryDbRequest: DbRequest {

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        let library = try database.autocreatedObject(ofType: RLibrary.self, forPrimaryKey: RLibrary.myLibraryId)

        guard library.0 else { return }

        library.1.name = "My Library"
        library.1.orderId = 1
        let versions = RVersions()
        database.add(versions)
        library.1.versions = versions
    }
}
