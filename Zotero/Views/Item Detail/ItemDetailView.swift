//
//  ItemDetailView.swift
//  Zotero
//
//  Created by Michal Rentka on 27/08/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemDetailView: View {
    @ObservedObject private(set) var store: ItemDetailStore

    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>
    @Environment(\.editMode) private var editMode: Binding<EditMode>
    @Environment(\.dbStorage) private var dbStorage: DbStorage

    var body: some View {
        Group {
            if self.editMode?.wrappedValue.isEditing == true {
                ItemDetailEditingView()
                    .onAppear {
                        self.store.startEditing()
                    }
                    .onDisappear {
                        self.store.saveChanges()
                    }
                    .environmentObject(self.store)
            } else {
                ItemDetailPreviewView()
                    .environmentObject(self.store)
            }
        }
        .navigationBarBackButtonHidden(self.editMode?.wrappedValue.isEditing == true)
        .navigationBarItems(trailing: self.trailingNavbarItems)
        .betterSheet(item: self.$store.state.presentedNote,
                     onDismiss: {
                        self.store.state.presentedNote = nil
                     },
                     content: { note in
                        Binding(self.$store.state.presentedNote).flatMap { note in
                            NoteEditorView(note: note, saveAction: self.store.saveNote)
                        }
                     })
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
                         TagPickerView(store: TagPickerStore(libraryId: self.store.state.libraryId,
                                                             selectedTags: Set(self.store.state.data.tags.map({ $0.id })),
                                                             dbStorage: self.dbStorage),
                                       saveAction: self.store.setTags)
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

            EditButton()
        }
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

        return ItemDetailView(store: store).environment(\.editMode, .constant(.active))
    }
}

#endif
