//
//  ExportLocalePickerState.swift
//  Zotero
//
//  Created by Michal Rentka on 14.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct ExportLocalePickerState: ViewModelState {
    let selected: String
    var locales: [ExportLocale]
    var loading: Bool

    init(selected: String) {
        self.selected = selected
        self.locales = []
        self.loading = true
    }

    func cleanup() {}
}
