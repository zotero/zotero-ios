//
//  CollectionPickerState.swift
//  Zotero
//
//  Created by Michal Rentka on 28/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct CollectionPickerState: ViewModelState {
    let library: Library
    let excludedKeys: Set<String>

    var collections: [Collection]
    var error: CollectionPickerError?
    var token: NotificationToken?
    var selected: Set<String>

    init(library: Library, excludedKeys: Set<String>, selected: Set<String>) {
        self.library = library
        self.excludedKeys = excludedKeys
        self.selected = selected
        self.collections = []
    }

    func cleanup() {}
}
