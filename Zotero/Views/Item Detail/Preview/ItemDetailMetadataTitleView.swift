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

    let title: String

    var body: some View {
        Text(self.title)
            .foregroundColor(.gray)
            .font(.headline)
            .fontWeight(.regular)
//            .background(ItemDetailMetadataTitleGeometry())
//            .frame(width: self.store.state.metadataTitleMaxWidth, alignment: .leading)
//            .onPreferenceChange(MetadataTitleWidthPreferenceKey.self, perform: {
//                if $0 > self.store.state.metadataTitleMaxWidth {
//                    // SWIFTUI BUG: - figure out how to calculate the max width
//                    self.store.state.metadataTitleMaxWidth = ceil($0-40)
//                }
//            })
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
                                    apiClient: controllers.apiClient,
                                    fileStorage: controllers.fileStorage,
                                    dbStorage: controllers.dbStorage,
                                    schemaController: controllers.schemaController)

        return List {
            ItemDetailMetadataTitleView(title: "bigbigbigbigbig title")
                .environmentObject(store)
        }
    }
}
