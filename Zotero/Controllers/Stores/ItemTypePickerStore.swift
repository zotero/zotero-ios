//
//  ItemTypePickerStore.swift
//  Zotero
//
//  Created by Michal Rentka on 23/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import Foundation

class ItemTypePickerStore: ObservableObject, TypePickerStore {
    @Published var state: TypePickerState

    init(selected: String , schemaController: SchemaController) {
        let types: [TypePickerData] = schemaController.itemTypes.compactMap { type in
            guard type != ItemTypes.attachment,
                  let name = schemaController.localized(itemType: type) else { return nil }
            return TypePickerData(key: type, value: name)
        }.sorted(by: { $0.value < $1.value })
        self.state = TypePickerState(data: types, selectedRow: selected)
    }
}
