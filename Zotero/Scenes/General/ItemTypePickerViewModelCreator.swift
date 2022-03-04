//
//  ItemTypePickerViewModelCreator.swift
//  Zotero
//
//  Created by Michal Rentka on 28/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct ItemTypePickerViewModelCreator {
    static func create(selected: String , schemaController: SchemaController) -> ViewModel<SinglePickerActionHandler> {
        let types: [SinglePickerModel] = schemaController.itemTypes.compactMap { type in
            guard !ItemTypes.excludedFromTypePicker.contains(type), let name = schemaController.localized(itemType: type) else { return nil }
            return SinglePickerModel(id: type, name: name)
        }.sorted(by: { $0.name < $1.name })
        let state = SinglePickerState(objects: types, selectedRow: selected)
        return ViewModel(initialState: state, handler: SinglePickerActionHandler())
    }
}
