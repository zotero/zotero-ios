//
//  CiteSearchState.swift
//  Zotero
//
//  Created by Michal Rentka on 04.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct CiteSearchState: ViewModelState {
    struct Changes: OptionSet {
        typealias RawValue = UInt8

        let rawValue: UInt8

        static let styles = Changes(rawValue: 1 << 0)
        static let loading = Changes(rawValue: 1 << 0)
    }

    let installedIds: Set<String>

    var changes: Changes
    var styles: [RemoteStyle]
    var filtered: [RemoteStyle]?
    var loading: Bool
    var error: Error?

    init(installedIds: Set<String>) {
        self.installedIds = installedIds
        self.changes = []
        self.styles = []
        self.loading = false
    }

    mutating func cleanup() {
        self.error = nil
        self.changes = []
    }
}
