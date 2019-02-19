//
//  ResolveReferenceDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 19/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ResolveReferenceDbRequest<Obj: Object>: DbResponseRequest {
    typealias Response = Obj

    let reference: ThreadSafeReference<Obj>

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Obj {
        guard let object = database.resolve(self.reference) else {
            throw DbError.objectNotFound
        }
        return object
    }
}

