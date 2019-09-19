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

    let librarySelected: (Library) -> Void

    var body: some View {
        List {
            Section {
                self.store.state.customLibraries.flatMap { libraries in
                    Section {
                        ForEach(libraries) { library in
                            Button(action: {
                                self.librarySelected(Library(customLibrary: library))
                            }) {
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
                            Button(action: {
                                self.librarySelected(Library(group: library))
                            }) {
                                LibraryRow(title: library.name)
                            }
                        }
                    }
                }
            }
        }.listStyle(GroupedListStyle())
    }
}

struct LibrariesView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            LibrariesView(store: LibrariesStore(dbStorage: Controllers().dbStorage)) { _ in }
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
