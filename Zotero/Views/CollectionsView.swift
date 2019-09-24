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

    @Environment(\.dbStorage) private var dbStorage: DbStorage

    let rowSelected: (Collection, Library) -> Void

    var body: some View {
        List {
            ForEach(self.store.state.collections) { collection in
                Button(action: {
                    self.store.state.selectedCollection = collection
                    self.rowSelected(collection, self.store.state.library)
                }) {
                    CollectionRow(data: collection)
                        .contextMenu(
                            collection.type.isCustom ?
                                nil :
                                ContextMenu {
                                    Button(action: {
                                        self.store.state.editingType = .edit(collection)
                                    }) {
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
                                    Button(action: {
                                        self.store.state.editingType = .addSubcollection(collection)
                                    }) {
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
        }
        .navigationBarTitle(Text(self.store.state.library.name), displayMode: .inline)
        .navigationBarItems(trailing: Button(action: { self.store.state.editingType = .add }, label: { Image(systemName: "plus") }))
        .sheet(item: self.$store.state.editingType, onDismiss: { self.store.state.editingType = nil }) { type in
            NavigationView {
                self.createEditView(with: type)
            }
            .navigationViewStyle(StackNavigationViewStyle())
        }
    }

    private func createEditView(with type: CollectionsStore.State.EditingType) -> CollectionEditView? {
        let key: String?
        let name: String
        let parent: Collection?

        switch type {
        case .add:
            key = nil
            name = ""
            parent = nil
        case .addSubcollection(let collection):
            key = nil
            name = ""
            parent = collection
        case .edit(let collection):
            let request = ReadCollectionDbRequest(libraryId: self.store.state.library.identifier, key: collection.key)
            let rCollection = try? self.dbStorage.createCoordinator().perform(request: request)

            key = collection.key
            name = collection.name
            parent = rCollection?.parent.flatMap { Collection(object: $0, level: 0) }
        }

        let store = NewCollectionEditStore(library: self.store.state.library,
                                           key: key,
                                           name: name,
                                           parent: parent,
                                           dbStorage: self.dbStorage)
        store.shouldDismiss = {
            self.store.state.editingType = nil
        }

        return CollectionEditView(store: store)
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
