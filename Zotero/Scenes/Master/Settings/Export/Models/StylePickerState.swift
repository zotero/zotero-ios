//
//  StylePickerState.swift
//  Zotero
//
//  Created by Michal Rentka on 14.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct StylePickerState: ViewModelState {
    let selected: String
    var results: Results<RStyle>?

    init(selected: String) {
        self.selected = selected
    }

    func cleanup() {}
}
