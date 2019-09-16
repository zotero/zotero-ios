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
    let controllers: Controllers

    var body: some View {
        List {
            ForEach(self.store.state.cellData) { cell in
                NavigationLink(destination: self.itemsView(from: cell)) {
                    CollectionRow(data: cell).deleteDisabled(cell.type.isCustom)
                }
            }
            .onDelete(perform: self.store.deleteCells)
        }.navigationBarTitle(Text(self.store.state.title), displayMode: .inline)
         .navigationBarItems(trailing: EditButton())
    }

    private func itemsView(from data: Collection) -> ItemsView {
        let type: NewItemsStore.State.ItemType

        switch data.type {
        case .collection:
            type = .collection(data.key, data.name)
        case .search:
            type = .search(data.key, data.name)
        case .custom(let customType):
            switch customType {
            case .all:
                type = .all
            case .publications:
                type = .publications
            case .trash:
                type = .trash
            }
        }

        return ItemsView(store: NewItemsStore(libraryId: self.store.state.libraryId,
                                              type: type,
                                              metadataEditable: self.store.state.metadataEditable,
                                              filesEditable: self.store.state.filesEditable,
                                              dbStorage: self.controllers.dbStorage))
    }
}

#if DEBUG

struct CollectionsView_Previews: PreviewProvider {
    static var previews: some View {
        let controllers = Controllers()
        let store = CollectionsStore(libraryId: .custom(.myLibrary),
                                     title: "Test",
                                     metadataEditable: true,
                                     filesEditable: true,
                                     dbStorage: controllers.dbStorage)
        return CollectionsView(store: store, controllers: controllers)
    }
}

#endif
