//
//  CollectionsView.swift
//  Zotero
//
//  Created by Michal Rentka on 20/08/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

import RealmSwift

struct CollectionsView: View {
    @ObservedObject private(set) var store: CollectionsStore

    let rowSelected: (Collection, Library) -> Void

    var body: some View {
        List {
            ForEach(self.store.state.cellData) { collection in
                CollectionRow(data: collection,
                              isSelected: (collection == self.store.state.selectedCollection))
                    .onTapGesture {
                        self.store.state.selectedCollection = collection
                        self.rowSelected(collection, self.store.state.library)
                    }
                    .deleteDisabled(collection.type.isCustom)
            }
            .onDelete(perform: self.store.deleteCells)
        }.navigationBarTitle(Text(self.store.state.library.name), displayMode: .inline)
         .navigationBarItems(trailing: EditButton())
    }
}

#if DEBUG

struct CollectionsView_Previews: PreviewProvider {
    static var previews: some View {
        let store = CollectionsStore(library: Library(identifier: .custom(.myLibrary), name: "My library",
                                                      metadataEditable: true, filesEditable: true),
                                     dbStorage: Controllers().dbStorage)
        return CollectionsView(store: store, rowSelected: { _, _ in })
    }
}

#endif
