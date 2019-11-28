//
//  ItemDetailMetadataTitleView.swift
//  Zotero
//
//  Created by Michal Rentka on 01/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemDetailMetadataTitleView: View {
    @EnvironmentObject private(set) var store: ItemDetailStore

    @Environment(\.editMode) private var editMode: Binding<EditMode>

    let title: String

    var body: some View {
        Text(self.title)
            .foregroundColor(.gray)
            .font(.headline)
            .fontWeight(.regular)
            .frame(width: self.maxWidth, alignment: .leading)
//            .background(ItemDetailMetadataTitleGeometry())
//            .frame(width: self.store.state.metadataTitleMaxWidth, alignment: .leading)
//            .onPreferenceChange(MetadataTitleWidthPreferenceKey.self, perform: {
//                if $0 > self.store.state.metadataTitleMaxWidth {
//                    // SWIFTUI BUG: - figure out how to calculate the max width
//                    self.store.state.metadataTitleMaxWidth = ceil($0-40)
//                }
//            })
    }

    private var maxWidth: CGFloat {
        // SWIFTUI BUG: - if I change the width based on editing value, the app crashes with
        // precondition failure: attribute failed to set an initial value: 98
        return self.store.state.data.maxFieldTitleWidth
//        return self.editMode?.wrappedValue.isEditing == true ? self.store.state.data.maxFieldTitleWidth :
//                                                               self.store.state.data.maxNonemptyFieldTitleWidth
    }
}

struct ItemDetailMetadataTitleGeometry: View {
    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(Color.clear)
                .preference(key: MetadataTitleWidthPreferenceKey.self, value: geometry.size.width)
        }
        .scaledToFill()
    }
}

struct ItemDetailMetadataTitleView_Previews: PreviewProvider {
    static var previews: some View {
        let controllers = Controllers()
        let store = ItemDetailStore(type: .creation(libraryId: .custom(.myLibrary),
                                                    collectionKey: nil,
                                                    filesEditable: true),
                                    userId: Defaults.shared.userId,
                                    apiClient: controllers.apiClient,
                                    fileStorage: controllers.fileStorage,
                                    dbStorage: controllers.userControllers!.dbStorage,
                                    schemaController: controllers.schemaController)

        return List {
            ItemDetailMetadataTitleView(title: "bigbigbigbigbig title")
                .environmentObject(store)
        }
    }
}
