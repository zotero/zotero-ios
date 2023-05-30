//
//  UpdateCollectionLastUsedDbRequest.swift
//  ZShare
//
//  Created by Michal Rentka on 31.03.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct UpdateCollectionLastUsedDbRequest: DbRequest {
    let key: String
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        guard let collection = database.objects(RCollection.self).filter(.key(self.key, in: self.libraryId)).first else { return }
        collection.lastUsed = Date()
    }
}
