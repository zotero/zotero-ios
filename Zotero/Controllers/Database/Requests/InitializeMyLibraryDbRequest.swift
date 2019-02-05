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
        let myLibrary = try database.autocreatedObject(ofType: RGroup.self, forPrimaryKey: RGroup.myLibraryId)
        myLibrary.name = "My Library"
    }
}
