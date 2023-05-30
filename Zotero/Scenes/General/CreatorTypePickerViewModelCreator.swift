//
//  CreatorTypePickerViewModelCreator.swift
//  Zotero
//
//  Created by Michal Rentka on 28/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct CreatorTypePickerViewModelCreator {
    static func create(itemType: String, selected: String, schemaController: SchemaController) -> ViewModel<SinglePickerActionHandler> {
        let creators = schemaController.creators(for: itemType) ?? []
        let models: [SinglePickerModel] = creators.compactMap { creator in
            guard let name = schemaController.localized(creator: creator.creatorType) else { return nil }
            return SinglePickerModel(id: creator.creatorType, name: name)
        }
        let state = SinglePickerState(objects: models, selectedRow: selected)
        return ViewModel(initialState: state, handler: SinglePickerActionHandler())
    }
}
