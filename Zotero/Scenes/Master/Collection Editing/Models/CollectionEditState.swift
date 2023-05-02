//
//  CollectionEditState.swift
//  Zotero
//
//  Created by Michal Rentka on 28/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct CollectionEditState: ViewModelState {
    let library: Library
    let key: String?

    var name: String
    var parent: Collection?
    var error: CollectionEditError?
    var loading: Bool
    var shouldDismiss: Bool
    var shouldCollapse: Bool

    init(library: Library, key: String?, name: String, parent: Collection?, shouldCollapse: Bool) {
        self.library = library
        self.key = key
        self.name = name
        self.parent = parent
        self.error = nil
        self.loading = false
        self.shouldDismiss = false
        self.shouldCollapse = shouldCollapse
    }

    func cleanup() {}
}
