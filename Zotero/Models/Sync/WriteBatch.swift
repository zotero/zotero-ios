//
//  WriteBatch.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct WriteBatch: Equatable {
    static let maxCount = 50
    let libraryId: LibraryIdentifier
    let object: SyncObject
    let version: Int
    let parameters: [[String: Any]]

    func copy(withVersion version: Int) -> WriteBatch {
        return WriteBatch(libraryId: self.libraryId, object: self.object, version: version, parameters: self.parameters)
    }

    // We don't really need equatability in this target, we need it for testing. Swift can't automatically
    // synthesize equatability function in an extension in a different file to the type. So I'm adding "placeholder"
    // equatability functions here so that Action equatability is synthesized automatically.
    static func ==(lhs: WriteBatch, rhs: WriteBatch) -> Bool {
        return true
    }
}
