//
//  LibrariesState.swift
//  Zotero
//
//  Created by Michal Rentka on 27/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

typealias DeleteGroupQuestion = (id: Int, name: String) // group id, name

struct LibrariesState: ViewModelState {
    struct Changes: OptionSet {
        typealias RawValue = UInt8

        let rawValue: UInt8

        static let groups = Changes(rawValue: 1 << 0)
        static let groupDeletion = Changes(rawValue: 1 << 0)
    }

    var customLibraries: Results<RCustomLibrary>?
    var groupLibraries: Results<RGroup>?
    var error: LibrariesError?
    var deleteGroupQuestion: DeleteGroupQuestion?
    var changes: Changes

    var groupsToken: NotificationToken?

    init() {
        self.changes = []
    }

    mutating func cleanup() {
        self.changes = []
        self.error = nil
        self.deleteGroupQuestion = nil
    }
}
