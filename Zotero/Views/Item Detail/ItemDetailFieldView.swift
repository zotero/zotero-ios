//
//  ItemDetailFieldView.swift
//  Zotero
//
//  Created by Michal Rentka on 30/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemDetailFieldView: View {
    @Binding var field: ItemDetailStore.State.Field
    let editingEnabled: Bool

    var body: some View {
        Group {
            if self.editingEnabled || !self.field.value.isEmpty {
                ItemDetailInputView(title: self.field.name, value: self.$field.value, editingEnabled: self.editingEnabled)
            } else {
                EmptyView()
            }
        }
    }
}

struct ItemDetailFieldsView_Previews: PreviewProvider {
    static var previews: some View {
        ItemDetailFieldView(field: .constant(ItemDetailStore.State.Field(key: "key",
                                                                         name: "Some item",
                                                                         value: "Some value",
                                                                         isTitle: false,
                                                                         changed: false)),
                            editingEnabled: false)
    }
}
