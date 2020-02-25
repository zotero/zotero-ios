//
//  CreatorTypePickerStore.swift
//  Zotero
//
//  Created by Michal Rentka on 24/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import Foundation

class CreatorTypePickerStore: ObservableObject, TypePickerStore {
    @Published var state: TypePickerState

    init(itemType: String, selected: String , schemaController: SchemaController) {
        let creators = schemaController.creators(for: itemType) ?? []
        let types: [TypePickerData] = creators.compactMap { creator in
            guard let name = schemaController.localized(creator: creator.creatorType) else { return nil }
            return TypePickerData(key: creator.creatorType, value: name)
        }
        self.state = TypePickerState(data: types, selectedRow: selected)
    }
}
