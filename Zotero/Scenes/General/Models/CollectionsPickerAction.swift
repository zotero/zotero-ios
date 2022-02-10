//
//  CollectionsPickerAction.swift
//  Zotero
//
//  Created by Michal Rentka on 28/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum CollectionsPickerAction {
    case loadData
    case select(Collection)
    case deselect(Collection)
    case setError(CollectionsPickerState.Error?)
}
