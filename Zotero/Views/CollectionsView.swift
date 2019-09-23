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
                Button(action: {
                    self.store.state.selectedCollection = collection
                    self.rowSelected(collection, self.store.state.library)
                }) {
                    CollectionRow(data: collection)
                        .contextMenu(
                            collection.type.isCustom ?
                                nil :
                                ContextMenu {
                                    Button(action: {}) {
                                        HStack {
                                            Image(systemName: "pencil.circle")
                                            Text("Edit")
                                        }
                                    }
                                    Button(action: { self.store.deleteCollection(with: collection.key) }) {
                                        HStack {
                                            Image(systemName: "minus.circle")
                                            Text("Delete")
                                        }
                                    }
                                    Button(action: {}) {
                                        HStack {
                                            Image(systemName: "plus.circle")
                                            Text("New subcollection")
                                        }
                                    }
                                }
                        )
                }
                .listRowBackground((collection == self.store.state.selectedCollection) ? Color.gray.opacity(0.4) : Color.white)
            }
        }.navigationBarTitle(Text(self.store.state.library.name), displayMode: .inline)
         .navigationBarItems(trailing: Button(action: {}, label: { Image(systemName: "plus") }))
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
