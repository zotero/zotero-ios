//
//  ItemsView.swift
//  Zotero
//
//  Created by Michal Rentka on 23/08/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

import RealmSwift

struct ItemsView: UIViewControllerRepresentable {
    let store: ItemsStore

    func makeUIViewController(context: Context) -> ItemsViewController {
        return ItemsViewController(store: self.store)
    }

    func updateUIViewController(_ uiViewController: ItemsViewController, context: Context) {

    }
}

#if DEBUG

struct ItemsView_Previews: PreviewProvider {
    static var previews: some View {
        let config = Realm.Configuration(inMemoryIdentifier: "swiftui")
        let storage = RealmDbStorage(config: config)
        let apiClient = ZoteroApiClient(baseUrl: ApiConstants.baseUrlString, headers: ["Zotero-API-Version": ApiConstants.version.description])
        let state = ItemsStore.StoreState(libraryId: .custom(.myLibrary), type: .all, metadataEditable: true, filesEditable: true)
        let store = ItemsStore(initialState: state,
                               apiClient: apiClient,
                               fileStorage: FileStorageController(),
                               dbStorage: storage,
                               schemaController: SchemaController(apiClient: apiClient, userDefaults: UserDefaults.standard))
        return ItemsView(store: store)
    }
}

#endif
