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
    @Environment(\.fileStorage) private var fileStorage: FileStorage
    @Environment(\.schemaController) private var schemaController: SchemaController

    var body: some View {
        NavigationView {
            CollectionsView()
                .environmentObject(CollectionsStore(library: self.defaultLibrary, dbStorage: self.dbStorage))
            ItemsView()
                .environmentObject(ItemsStore(type: .all,
                                              library: self.defaultLibrary,
                                              dbStorage: self.dbStorage,
                                              fileStorage: self.fileStorage,
                                              schemaController: self.schemaController))
        }
    }

    private var defaultLibrary: Library {
        return Library(identifier: .custom(.myLibrary),
                       name: RCustomLibraryType.myLibrary.libraryName,
                       metadataEditable: true,
                       filesEditable: true)
    }
}

#if DEBUG

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
    }
}

#endif
