//
//  ItemDetailView.swift
//  Zotero
//
//  Created by Michal Rentka on 27/08/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemDetailView: View {
    @EnvironmentObject private(set) var store: ItemDetailStore

    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>
    @Environment(\.editMode) private var editMode: Binding<EditMode>
    @Environment(\.dbStorage) private var dbStorage: DbStorage

    var body: some View {
        Group {
            if self.editMode?.wrappedValue.isEditing == true {
                ItemDetailEditingView()
            } else {
                ItemDetailPreviewView()
            }
        }
        .onAppear(perform: {
            if self.store.state.type.isCreation {
                self.store.startEditing()
                self.editMode?.wrappedValue = .active
            }
        })
        .navigationBarBackButtonHidden(self.editMode?.wrappedValue.isEditing == true)
        .navigationBarItems(trailing: self.trailingNavbarItems)
        .betterSheet(item: self.$store.state.unknownAttachment,
                     onDismiss: {
                         self.store.state.unknownAttachment = nil
                     },
                     content: { url in
                         ActivityView(activityItems: [url], applicationActivities: nil)
                     })
         .betterSheet(isPresented: self.$store.state.showTagPicker,
                      onDismiss: {
                         self.store.state.showTagPicker = false
                      },
                      content: {
                         TagPickerView(saveAction: self.store.setTags)
                            .environmentObject(TagPickerStore(libraryId: self.store.state.libraryId,
                                                              selectedTags: Set(self.store.state.data.tags.map({ $0.id })),
                                                              dbStorage: self.dbStorage))
                      })
    }

    private var trailingNavbarItems: some View {
        HStack {
            if self.editMode?.wrappedValue.isEditing == true {
                Button(action: {
                    self.store.cancelChanges()
                    if self.store.state.type.isCreation {
                        self.presentationMode.wrappedValue.dismiss()
                    } else {
                        self.editMode?.animation().wrappedValue = .inactive
                    }
                }) {
                    Text("Cancel")
                }
            }

            Button(action: {
                if self.editMode?.wrappedValue.isEditing == true {
                    if self.store.saveChanges() {
                        self.editMode?.wrappedValue = .inactive
                    }
                } else {
                    self.store.startEditing()
                    self.editMode?.wrappedValue = .active
                }
            }) {
                Text(self.editMode?.wrappedValue.isEditing == true ? "Save" : "Edit")
            }
        }
        // SWIFTUI BUG: - when changing between 1 and 2 buttons, the frame keeps the wider widht of 2 buttons and the single button is
        // centered to the middle, by setting a big frame we create the same width for both states and align them to the right
        .frame(width: 100, alignment: .trailing)
    }
}

extension URL: Identifiable {
    public var id: URL {
        return self
    }
}

fileprivate extension EditMode {
    mutating func toggle() {
        self = self == .active ? .inactive : .active
    }
}

#if DEBUG

struct ItemDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let controllers = Controllers()
        controllers.schemaController.reloadSchemaIfNeeded()
        let store = ItemDetailStore(type: .creation(libraryId: .custom(.myLibrary),
                                                    collectionKey: nil, filesEditable: true),
                                    apiClient: controllers.apiClient,
                                    fileStorage: controllers.fileStorage,
                                    dbStorage: controllers.dbStorage,
                                    schemaController: controllers.schemaController)

        return ItemDetailView()
                    .environment(\.editMode, .constant(.active))
                    .environmentObject(store)
    }
}

#endif
