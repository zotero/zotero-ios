//
//  MarkObjectAsDeletedDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 06/05/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct MarkObjectAsDeletedDbRequest<Obj: DeletableObject>: DbRequest {
    let key: String
    let libraryId: LibraryIdentifier

    var needsWrite: Bool {
        return true
    }

    func process(in database: Realm) throws {
        guard let object = database.objects(Obj.self).filter(Predicates.key(self.key, in: self.libraryId)).first else {
            throw DbError.objectNotFound
        }
        object.deleted = true
    }
}
