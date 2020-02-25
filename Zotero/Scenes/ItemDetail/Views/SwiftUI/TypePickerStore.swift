//
//  TypePickerStore.swift
//  Zotero
//
//  Created by Michal Rentka on 24/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct TypePickerData: Identifiable {
    let key: String
    let value: String

    var id: String { return self.key }
}

struct TypePickerState {
    var data: [TypePickerData]
    var selectedRow: String
}

protocol TypePickerStore: class {
    var state: TypePickerState { get set }
}
