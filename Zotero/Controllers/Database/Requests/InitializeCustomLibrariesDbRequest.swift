//
//  InitializeCustomLibrariesDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 05/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct InitializeCustomLibrariesDbRequest: DbResponseRequest {
    typealias Response = Bool

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws -> Bool {
        guard database.object(ofType: RCustomLibrary.self, forPrimaryKey: RCustomLibraryType.myLibrary.rawValue) == nil else { return false }

        let library = RCustomLibrary()
        library.type = .myLibrary
        library.orderId = 1
        library.versions = RVersions()
        database.add(library)

        return true
    }
}
