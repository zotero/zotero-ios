//
//  ItemsView.swift
//  Zotero
//
//  Created by Michal Rentka on 23/08/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

import RealmSwift

struct ItemsView: View {
    @ObservedObject private(set) var store: ItemsStore
    
    @Environment(\.editMode) private var editMode: Binding<EditMode>
    @Environment(\.dbStorage) private var dbStorage: DbStorage
    @Environment(\.apiClient) private var apiClient: ApiClient
    @Environment(\.schemaController) private var schemaController: SchemaController
    @Environment(\.fileStorage) private var fileStorage: FileStorage

    var body: some View {
        VStack {
            NavigationLink(destination: self.itemCreationView,
                           isActive: self.$store.state.showingCreation,
                           label: { EmptyView() })

            List(selection: self.$store.state.selectedItems) {
                self.store.state.sections.flatMap {
                    ForEach($0, id: \.self) { section in
                        self.store.state.items(for: section).flatMap { items in
                            ItemSectionView(results: items,
                                            libraryId: self.store.state.library.identifier)
                        }
                    }
                }
            }
            
            if self.editMode?.wrappedValue.isEditing == true {
                Toolbar().environmentObject(self.store)
            }
        }
        .onAppear(perform: { self.store.state.showingCreation = false })
        .overlay(ActionSheetOverlay().environmentObject(self.store))
        .navigationBarTitle(self.navigationBarTitle, displayMode: .inline)
        .navigationBarItems(trailing: self.trailingItems)
        .edgesIgnoringSafeArea(.bottom)
    }
    
    private var navigationBarTitle: Text {
        if self.editMode?.wrappedValue.isEditing == true {
            switch self.store.state.selectedItems.count {
            case 0:
                return Text("Select Items")
            case 1:
                return Text("1 Item Selected")
            default:
                return Text("\(self.store.state.selectedItems.count) Items Selected")
            }
        }
        return Text("")
    }

    private var trailingItems: some View {
        Group {
            if self.editMode?.wrappedValue.isEditing == true {
                Button(action: {
                    self.editMode?.animation().wrappedValue = .inactive
                }, label: {
                    Text("Done")
                })
            } else {
                Button(action: {
                    withAnimation {
                        self.store.state.menuActionSheetPresented = true
                    }
                }) {
                    Image(systemName: "ellipsis")
                }
            }
        }
    }
    
    private var itemCreationView: some View {
        ItemDetailView(store: ItemDetailStore(type: .creation(libraryId: self.store.state.library.identifier,
                                                              collectionKey: nil,
                                                              filesEditable: self.store.state.library.filesEditable),
                                              apiClient: self.apiClient,
                                              fileStorage: self.fileStorage,
                                              dbStorage: self.dbStorage,
                                              schemaController: self.schemaController))
    }
}

fileprivate struct ActionSheetOverlay: View {
    @EnvironmentObject private(set) var store: ItemsStore
    
    @Environment(\.editMode) private var editMode: Binding<EditMode>
    
    var body: some View {
        Group {
            if self.store.state.menuActionSheetPresented {
                ZStack(alignment: .topTrailing) {
                    Color.black.opacity(0.1)
                        .onTapGesture {
                            withAnimation {
                                self.store.state.menuActionSheetPresented = false
                            }
                        }

                    VStack(alignment: .leading, spacing: 12) {
                        Button(action: {
                            self.editMode?.animation().wrappedValue = .active
                            self.store.state.menuActionSheetPresented = false
                        }) {
                            Text("Select Items")
                        }
                        Divider()
                        Button(action: {}) {
                            Text("Sort By: \(self.sortByTitle)")
                        }
                        Button(action: { self.store.state.sortType.ascending.toggle() }) {
                            Text("Sort Order: \(self.sortOrderTitle)")
                        }
                        Divider()
                        Button(action: { self.store.state.showingCreation = true }) {
                            Text("New Item")
                        }
                    }
                    .padding()
                    .frame(width: 260, alignment: .trailing)
                    .background(Color.white)
                }
            } else {
                EmptyView()
            }
        }
    }
    
    private var sortByTitle: String {
        switch self.store.state.sortType.field {
        case .title:
            return "Title"
        }
    }
    
    private var sortOrderTitle: String {
        return self.store.state.sortType.ascending ? "Ascending" : "Descending"
    }
}

fileprivate struct Toolbar: View {
    @EnvironmentObject private(set) var store: ItemsStore
    
    var body: some View {
        HStack {
            Spacer()
            
            Button(action: {
                
            }) {
                Image(systemName: "folder.badge.plus")
                    .imageScale(.large)
            }
            .disabled(self.store.state.selectedItems.isEmpty)
            
            Spacer()
            
            Button(action: {
                
            }) {
                Image(systemName: "trash")
                .imageScale(.large)
            }
            .disabled(self.store.state.selectedItems.isEmpty)
            
            Spacer()
            
            Button(action: {
                
            }) {
                Image(systemName: "square.on.square")
                .imageScale(.large)
            }
            .disabled(self.store.state.selectedItems.count != 1)
            
            Spacer()
        }
        .padding(.vertical)
        .padding(.bottom, 20)
        .background(Color.gray.opacity(0.05))
    }
}

fileprivate struct ItemSectionView: View {
    let results: Results<RItem>
    let libraryId: LibraryIdentifier

    @Environment(\.dbStorage) private var dbStorage: DbStorage
    @Environment(\.apiClient) private var apiClient: ApiClient
    @Environment(\.schemaController) private var schemaController: SchemaController
    @Environment(\.fileStorage) private var fileStorage: FileStorage

    var body: some View {
        Section {
            ForEach(self.results, id: \.key) { item in
                NavigationLink(destination: ItemDetailView(store: self.detailStore(for: item))) {
                    ItemRow(item: item)
                }
            }
        }
    }

    private func detailStore(for item: RItem) -> ItemDetailStore {
        return ItemDetailStore(type: .preview(item),
                               apiClient: self.apiClient,
                               fileStorage: self.fileStorage,
                               dbStorage: self.dbStorage,
                               schemaController: self.schemaController)
    }
}

#if DEBUG

struct ItemsView_Previews: PreviewProvider {
    static var previews: some View {
        ItemsView(store: ItemsStore(type: .all,
                                       library: Library(identifier: .custom(.myLibrary), name: "My library",
                                                        metadataEditable: true, filesEditable: true),
                                       dbStorage: Controllers().dbStorage))
    }
}

#endif
