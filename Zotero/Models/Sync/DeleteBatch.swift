//
//  DeleteBatch.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct DeleteBatch: Equatable {
    static let maxCount = 50
    let libraryId: LibraryIdentifier
    let object: SyncObject
    let version: Int
    let keys: [String]

    func copy(withVersion version: Int) -> DeleteBatch {
        return DeleteBatch(libraryId: self.libraryId, object: self.object, version: version, keys: self.keys)
    }

    // We don't really need equatability in this target, we need it for testing. Swift can't automatically
    // synthesize equatability function in an extension in a different file to the type. So I'm adding "placeholder"
    // equatability functions here so that SyncAction equatability is synthesized automatically.
    static func ==(lhs: DeleteBatch, rhs: DeleteBatch) -> Bool {
        return true
    }
}
