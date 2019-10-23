//
//  ItemTypePickerStore.swift
//  Zotero
//
//  Created by Michal Rentka on 23/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import Foundation

class ItemTypePickerStore: ObservableObject {
    struct State {
        struct ItemType: Identifiable {
            let key: String
            let name: String

            var id: String { return self.key }
        }

        var data: [ItemType]
        var selectedType: String
    }

    @Published var state: State

    init(selected: String , schemaController: SchemaController) {
        let types: [State.ItemType] = schemaController.itemTypes.compactMap { type in
            guard let name = schemaController.localized(itemType: type) else { return nil }
            return State.ItemType(key: type, name: name)
        }
        self.state = State(data: types, selectedType: selected)
    }
}
