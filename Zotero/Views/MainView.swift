//
//  MainView.swift
//  Zotero
//
//  Created by Michal Rentka on 26/08/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct MainView: View {
    private var defaultLibrary: Library {
        return Library(identifier: .custom(.myLibrary),
                       name: RCustomLibraryType.myLibrary.libraryName,
                       metadataEditable: true,
                       filesEditable: true)
    }

    @Environment(\.dbStorage) private var dbStorage: DbStorage

    var body: some View {
        NavigationView {
            CollectionsView(store: CollectionsStore(library: self.defaultLibrary,
                                                    dbStorage: self.dbStorage)) { _, _ in }
            ItemsView(store: NewItemsStore(type: .all,
                                           library: self.defaultLibrary,
                                           dbStorage: self.dbStorage))
        }
    }
}

#if DEBUG

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
    }
}

#endif
