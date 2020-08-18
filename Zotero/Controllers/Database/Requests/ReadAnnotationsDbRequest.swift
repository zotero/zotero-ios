//
//  ReadAnnotationsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 18/08/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadAnnotationsDbRequest: DbResponseRequest {
    typealias Response = Results<RAnnotation>

    let itemKey: String
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Results<RAnnotation> {
        return database.objects(RAnnotation.self).filter(.itemKey(self.itemKey, in: self.libraryId)).sorted(byKeyPath: "sortIndex")
    }
}
