//
//  ItemDetailEditCreatorView.swift
//  Zotero
//
//  Created by Michal Rentka on 01/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemDetailEditCreatorView: View {
    @Binding var creator: ItemDetailStore.State.Creator

    @EnvironmentObject private var store: ItemDetailStore

    @Environment(\.schemaController) private var schemaController: SchemaController

    var body: some View {
        HStack {
            ItemDetailMetadataTitleView(title: self.creator.localizedType)
            .onTapGesture {
                NotificationCenter.default.post(name: .presentCreatorPicker, object: (self.store.state.data.type, self.store.state.libraryId, self.creator.type, self.set))
            }
            if self.creator.namePresentation == .full {
                TextField("Full name", text: self.$creator.fullName)
            } else if self.creator.namePresentation == .separate {
                TextField("Last name", text: self.$creator.lastName)
                Text(", ")
                TextField("First name", text: self.$creator.firstName)
            }
            Spacer()
            // SWIFTUI BUG: - Button action in cell not called in EditMode.active
            Button(action: {
                self.creator.namePresentation.toggle()
            }) {
                Text(self.creator.namePresentation == .full ? "Split name" : "Merge name").foregroundColor(.blue)
            }.onTapGesture {
                self.creator.namePresentation.toggle()
            }
        }
    }

    private func set(type: String) {
        guard let localized = self.schemaController.localized(creator: type) else { return }
        self.creator.type = type
        self.creator.localizedType = localized
    }
}

struct ItemDetailEditCreatorView_Previews: PreviewProvider {
    static var previews: some View {
        let controllers = Controllers()
        controllers.schemaController.reloadSchemaIfNeeded()
        let store = ItemDetailStore(type: .creation(libraryId: .custom(.myLibrary),
                                                    collectionKey: nil, filesEditable: true),
                                    apiClient: controllers.apiClient,
                                    fileStorage: controllers.fileStorage,
                                    dbStorage: controllers.dbStorage,
                                    schemaController: controllers.schemaController)
        return ItemDetailEditCreatorView(creator: .constant(.init(type: "test", primary: false, localizedType: "Test")))
                    .environmentObject(store)
    }
}
