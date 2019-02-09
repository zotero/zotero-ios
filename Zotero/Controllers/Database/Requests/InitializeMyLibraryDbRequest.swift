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
        let myLibrary = try database.autocreatedObject(ofType: RLibrary.self, forPrimaryKey: RLibrary.myLibraryId).1
        myLibrary.name = "My Library"
        if myLibrary.versions == nil {
            let versions = RVersions()
            database.add(versions)
            myLibrary.versions = versions
        }
    }
}
