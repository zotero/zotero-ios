//
//  SinglePickerState.swift
//  Zotero
//
//  Created by Michal Rentka on 28/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct SinglePickerState: ViewModelState {
    var objects: [SinglePickerModel]
    var selectedRow: String

    func cleanup() {}
}
