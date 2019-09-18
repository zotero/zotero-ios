//
//  MainView.swift
//  Zotero
//
//  Created by Michal Rentka on 26/08/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct MainView: View {

    @Environment(\.dbStorage) private var dbStorage: DbStorage

    var body: some View {
        NavigationView {
            CollectionsView(store: self.defaultCollectionsStore)
            ItemsView(store: self.defaultItemsStore)
        }
    }

    private var defaultCollectionsStore: CollectionsStore {
        return CollectionsStore(libraryId: .custom(.myLibrary),
                                title: RCustomLibraryType.myLibrary.libraryName,
                                metadataEditable: true,
                                filesEditable: true,
                                dbStorage: self.dbStorage)
    }

    private var defaultItemsStore: NewItemsStore {
        return NewItemsStore(libraryId: .custom(.myLibrary),
                             type: .all,
                             metadataEditable: true,
                             filesEditable: true,
                             dbStorage: self.dbStorage)
    }
}

#if DEBUG

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
    }
}

#endif
