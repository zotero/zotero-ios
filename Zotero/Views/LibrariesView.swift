//
//  LibrariesView.swift
//  Zotero
//
//  Created by Michal Rentka on 18/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct LibrariesView: View {
    @ObservedObject private(set) var store: LibrariesStore

    @Environment(\.dbStorage) private var dbStorage: DbStorage

    var body: some View {
        List {
            Section {
                self.store.state.customLibraries.flatMap { libraries in
                    Section {
                        ForEach(libraries) { library in
                            NavigationLink(destination: CollectionsView(store: self.store(for: library))) {
                                LibraryRow(title: library.type.libraryName)
                            }
                        }
                    }
                }
            }

            Section(header: Text("Group Libraries")) {
                self.store.state.groupLibraries.flatMap { libraries in
                    Section {
                        ForEach(libraries) { library in
                            NavigationLink(destination: CollectionsView(store: self.store(for: library))) {
                                LibraryRow(title: library.name)
                            }
                        }
                    }
                }
            }
        }.listStyle(GroupedListStyle())
    }

    private func store(for library: RCustomLibrary) -> CollectionsStore {
        return CollectionsStore(libraryId: .custom(library.type),
                                title: library.type.libraryName,
                                metadataEditable: true,
                                filesEditable: true,
                                dbStorage: self.dbStorage)
    }

    private func store(for library: RGroup) -> CollectionsStore {
        return CollectionsStore(libraryId: .group(library.identifier),
                                title: library.name,
                                metadataEditable: library.canEditMetadata,
                                filesEditable: library.canEditFiles,
                                dbStorage: self.dbStorage)
    }
}

struct LibrariesView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            LibrariesView(store: LibrariesStore(dbStorage: Controllers().dbStorage))
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

extension RCustomLibrary: Identifiable {
    var id: Int {
        return self.rawType
    }
}

extension RGroup: Identifiable {
    var id: Int {
        return self.identifier
    }
}
