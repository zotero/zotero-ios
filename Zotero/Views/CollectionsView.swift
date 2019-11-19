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
    @EnvironmentObject private(set) var store: CollectionsStore

    @Environment(\.dbStorage) private var dbStorage: DbStorage

    var body: some View {
        List {
            ForEach(self.store.state.collections) { collection in
                CollectionRowButton(collection: collection)
            }
        }
        .listStyle(PlainListStyle())
        .navigationBarTitle(Text(self.store.state.library.name), displayMode: .inline)
        .navigationBarItems(trailing: Button(action: { self.store.state.editingType = .add }, label: { Image(systemName: "plus") }))
        .sheet(item: self.$store.state.editingType, onDismiss: { self.store.state.editingType = nil }) { type in
            NavigationView {
                self.createEditView(with: type)
            }
            .navigationViewStyle(StackNavigationViewStyle())
        }
    }

    private func createEditView(with type: CollectionsStore.State.EditingType) -> some View {
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

        let store = CollectionEditStore(library: self.store.state.library,
                                           key: key,
                                           name: name,
                                           parent: parent,
                                           dbStorage: self.dbStorage)
        store.shouldDismiss = {
            self.store.state.editingType = nil
        }

        return CollectionEditView(closeAction: {})
                    .environment(\.dbStorage, self.dbStorage)
                    .environmentObject(store)
    }
}

fileprivate struct CollectionRowButton: View {
    @EnvironmentObject private(set) var store: CollectionsStore

    let collection: Collection

    var body: some View {
        Button(action: { self.store.state.selectedCollection = self.collection }) {
            CollectionRow(data: self.collection)
                .contextMenu(
                    self.collection.type.isCustom ?
                        nil :
                        ContextMenu {
                            Button(action: {
                                self.store.state.editingType = .edit(self.collection)
                            }) {
                                HStack {
                                    Text("Edit")
                                    Image(systemName: "pencil")
                                }
                            }
                            Button(action: {
                                self.store.state.editingType = .addSubcollection(self.collection)
                            }) {
                                HStack {
                                    Text("New subcollection")
                                    Image(systemName: "plus")
                                }
                            }
                            Divider()
                            Button(action: { self.store.deleteCollection(with: self.collection.key) }) {
                                HStack {
                                    Text("Delete")
                                    Image(systemName: "minus")
                                }
                                .foregroundColor(.red)
                            }
                        }
                )
        }
        .listRowInsets(EdgeInsets(top: 0,
                                  leading: self.inset(for: self.collection.level),
                                  bottom: 0,
                                  trailing: 0))
        .listRowBackground((self.collection == self.store.state.selectedCollection) ?
                                Color.gray.opacity(0.4) :
                                Color.white)
        .onAppear(perform: self.store.didAppear)
    }

    private func inset(for level: Int) -> CGFloat {
        return CollectionRow.levelOffset + (CGFloat(level) * CollectionRow.levelOffset)
    }
}

//struct CollectionsView_Previews: PreviewProvider {
//    static var previews: some View {
//        let store = CollectionsStore(library: Library(identifier: .custom(.myLibrary), name: "My library",
//                                                      metadataEditable: true, filesEditable: true),
//                                     dbStorage: Controllers().dbStorage)
//        return CollectionsView()
//                    .environmentObject(store)
//    }
//}
