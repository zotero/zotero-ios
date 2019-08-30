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
            .onDelete(perform: self.delete)
        }
        .onAppear {
            self.store.handle(action: .load)
        }
    }

    private func itemsView(from data: CollectionCellData) -> ItemsView {
        let type: ItemsStore.StoreState.ItemType

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

        let state = ItemsStore.StoreState(libraryId: self.store.state.libraryId, type: type,
                                          metadataEditable: true, filesEditable: true)
        return ItemsView(store: ItemsStore(initialState: state,
                                           apiClient: self.controllers.apiClient,
                                           fileStorage: self.controllers.fileStorage,
                                           dbStorage: self.controllers.dbStorage,
                                           schemaController: self.controllers.schemaController))
    }
    
    private func delete(at offsets: IndexSet) {
        self.store.handle(action: .deleteCells(offsets))
    }
}

#if DEBUG

struct CollectionsView_Previews: PreviewProvider {
    static var previews: some View {
        let controllers = Controllers()
        let state = CollectionsStore.StoreState(libraryId: .custom(.myLibrary),
                                                title: "Test",
                                                metadataEditable: true,
                                                filesEditable: true)
        let store = CollectionsStore(initialState: state,
                                     dbStorage: controllers.dbStorage)

        return CollectionsView(store: store, controllers: controllers)
    }
}

#endif
