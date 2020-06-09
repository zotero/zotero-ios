//
//  DownloadBatch.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct DownloadBatch: Equatable {
    static let maxCount = 50
    let libraryId: LibraryIdentifier
    let object: SyncObject
    let keys: [String]
    let version: Int

    // We don't really need equatability in this target, we need it for testing. Swift can't automatically
    // synthesize equatability function in an extension in a different file to the type. So I'm adding "placeholder"
    // equatability functions here so that Action equatability is synthesized automatically.
    static func ==(lhs: DownloadBatch, rhs: DownloadBatch) -> Bool {
        return true
    }
}
