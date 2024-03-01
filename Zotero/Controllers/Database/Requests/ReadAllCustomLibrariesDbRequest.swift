//
//  ReadAllCustomLibrariesDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 10/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadCustomLibrary: DbResponseRequest {
    typealias Response = RCustomLibrary

    let type: RCustomLibraryType

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> RCustomLibrary {
        guard let library = database.objects(RCustomLibrary.self).filter("type == %@", type).first else {
            throw DbError.objectNotFound
        }
        return library
    }
}

struct ReadAllCustomLibrariesDbRequest: DbResponseRequest {
    typealias Response = Results<RCustomLibrary>

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Results<RCustomLibrary> {
        return database.objects(RCustomLibrary.self).sorted(byKeyPath: "orderId")
    }
}
