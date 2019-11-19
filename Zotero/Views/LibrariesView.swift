//
//  LibrariesView.swift
//  Zotero
//
//  Created by Michal Rentka on 18/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct LibrariesView: View {
    @EnvironmentObject private(set) var store: LibrariesStore

    @Environment(\.dbStorage) private var dbStorage: DbStorage

    let pushCollectionsView: (Library) -> Void

    var body: some View {
        List {
            Section {
                self.store.state.customLibraries.flatMap { libraries in
                    Section {
                        ForEach(libraries) { library in
                            Button(action: {
                                self.pushCollectionsView(Library(customLibrary: library))
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
                                self.pushCollectionsView(Library(group: library))
                            }) {
                                LibraryRow(title: library.name)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(GroupedListStyle())
        .navigationBarItems(trailing:
            Button(action: { NotificationCenter.default.post(name: .presentSettings, object: nil) },
                   label: { Image(systemName: "person.circle").imageScale(.large) })
        )
    }
}

struct LibrariesView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            LibrariesView(pushCollectionsView: { _ in })
                .environmentObject(LibrariesStore(dbStorage: Controllers().userControllers!.dbStorage))
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
