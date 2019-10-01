//
//  ItemDetailView.swift
//  Zotero
//
//  Created by Michal Rentka on 27/08/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

import BetterSheet

struct ItemDetailView: View {
    @ObservedObject private(set) var store: ItemDetailStore

    @Environment(\.editMode) private var editMode: Binding<EditMode>
    @Environment(\.dbStorage) private var dbStorage: DbStorage

    var body: some View {
        Group {
            if self.editMode?.wrappedValue.isEditing == true {
                ItemDetailEditingView()
                    .environmentObject(self.store)
                    .transition(.slide)
                    .navigationBarItems(trailing: self.editNavbarItems)
                    .navigationBarBackButtonHidden(true)
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
            } else {
                ItemDetailPreviewView()
                    .environmentObject(self.store)
                    .transition(.slide)
                    .navigationBarItems(trailing: self.previewNavbarItems)
                    .navigationBarBackButtonHidden(false)
                    // SWIFTUI BUG: - somehow assign binding note to NoteEditingView
                    .betterSheet(item: self.$store.state.presentedNote,
                                 onDismiss: {
                                    self.store.state.presentedNote = nil
                                 },
                                 content: { note in
                                    NoteEditingView(note: note, saveAction: self.store.saveNote)
                                 })
                    .betterSheet(item: self.$store.state.unknownAttachment,
                                 onDismiss: {
                                     self.store.state.unknownAttachment = nil
                                 },
                                 content: { url in
                                     ActivityView(activityItems: [url], applicationActivities: nil)
                                 })
            }
        }
    }

    private var previewNavbarItems: some View {
        HStack {
            Button(action: {
                withAnimation {
                    self.store.startEditing()
                    self.editMode?.animation().wrappedValue = .active
                }
            }) {
                Text("Edit")
            }
        }
    }

    private var editNavbarItems: some View {
        HStack {
            Button(action: {
                withAnimation {
                    self.store.cancelChanges()
                    self.editMode?.animation().wrappedValue = .inactive
                }
            }) {
                Text("Cancel")
            }
            Button(action: {
                withAnimation {
                    self.store.saveChanges()
                    self.editMode?.animation().wrappedValue = .inactive
                }
            }) {
                Text("Done")
            }
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
