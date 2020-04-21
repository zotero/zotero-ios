//
//  LibrariesView.swift
//  Zotero
//
//  Created by Michal Rentka on 18/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct LibrariesView: View {
    @EnvironmentObject var viewModel: ViewModel<LibrariesActionHandler>

    @Environment(\.dbStorage) private var dbStorage: DbStorage

    weak var coordinatorDelegate: MasterLibrariesCoordinatorDelegate?

    var body: some View {
        List {
            Section {
                self.viewModel.state.customLibraries.flatMap { libraries in
                    Section {
                        ForEach(libraries) { library in
                            Button(action: {
                                self.coordinatorDelegate?.showCollections(for: Library(customLibrary: library))
                            }) {
                                LibraryRow(title: library.type.libraryName)
                            }
                        }
                    }
                }
            }

            Section(header: Text(L10n.Libraries.groupLibraries)) {
                self.viewModel.state.groupLibraries.flatMap { libraries in
                    Section {
                        ForEach(libraries) { library in
                            Button(action: {
                                self.coordinatorDelegate?.showCollections(for: Library(group: library))
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
            Button(action: {
                self.coordinatorDelegate?.showSettings()
            }, label: {
                Image(systemName: "person.circle").imageScale(.large)
            })
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.viewModel.process(action: .loadData)
            }
        }
    }
}

struct LibrariesView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            LibrariesView()
                .environmentObject(ViewModel(initialState: LibrariesState(),
                                             handler: LibrariesActionHandler(dbStorage: Controllers().userControllers!.dbStorage)))
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
