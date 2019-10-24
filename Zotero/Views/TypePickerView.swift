//
//  TypePickerView.swift
//  Zotero
//
//  Created by Michal Rentka on 23/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct TypePickerView<Store: ObservableObject&TypePickerStore>: View {
    @EnvironmentObject private var store: Store

    let saveAction: (String) -> Void
    let closeAction: () -> Void

    var body: some View {
        List {
            ForEach(self.store.state.data) { data in
                Button(action: {
                    self.store.state.selectedRow = data.key
                }) {
                    TypePickerRow(text: data.value, isSelected: self.store.state.selectedRow == data.key)
                }
            }
        }
        .navigationBarItems(leading: self.leadingItems, trailing: self.trailingItems)
    }

    private var leadingItems: some View {
        Button(action: self.closeAction) {
            Text("Cancel")
        }
    }

    private var trailingItems: some View {
        Button(action: {
            self.closeAction()
            self.saveAction(self.store.state.selectedRow)
        }) {
            Text("Save")
        }
    }
}

struct TypePickerView_Previews: PreviewProvider {
    static var previews: some View {
        TypePickerView<ItemTypePickerStore>(saveAction: { _ in }, closeAction: {})
            .environmentObject(ItemTypePickerStore(selected: "", schemaController: Controllers().schemaController))
    }
}
