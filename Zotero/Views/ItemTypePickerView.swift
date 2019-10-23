//
//  ItemTypePickerView.swift
//  Zotero
//
//  Created by Michal Rentka on 23/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemTypePickerView: View {
    @EnvironmentObject private var store: ItemTypePickerStore

    let saveAction: (String) -> Void
    let closeAction: () -> Void

    var body: some View {
        List {
            ForEach(self.store.state.data) { type in
                Button(action: {
                    self.store.state.selectedType = type.key
                }) {
                    HStack {
                        Text(type.name)
                        if self.store.state.selectedType == type.key {
                            Spacer()
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
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
            self.saveAction(self.store.state.selectedType)
            self.closeAction()
        }) {
            Text("Save")
        }
    }
}

struct ItemTypePickerView_Previews: PreviewProvider {
    static var previews: some View {
        ItemTypePickerView(saveAction: { _ in }, closeAction: {})
    }
}
