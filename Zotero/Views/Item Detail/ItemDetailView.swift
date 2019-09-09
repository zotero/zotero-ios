//
//  ItemDetailView.swift
//  Zotero
//
//  Created by Michal Rentka on 27/08/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemDetailView: View {
    @ObservedObject private(set) var store: NewItemDetailStore
    @Environment(\.editMode) private var editMode: Binding<EditMode>
    private var isEditing: Bool {
        return self.editMode?.wrappedValue.isEditing ?? false
    }

    var body: some View {
        List {
            ItemDetailTitleView(title: self.$store.state.data.title,
                                editingEnabled: self.isEditing)

            FieldsSection(type: self.store.state.data.localizedType,
                          visibleFields: self.store.state.data.visibleFields,
                          fields: self.$store.state.data.fields,
                          creators: self.$store.state.data.creators,
                          abstract: self.$store.state.data.abstract,
                          isEditing: self.isEditing,
                          deleteCreators: self.store.deleteCreators,
                          moveCreators: self.store.moveCreators,
                          addCreator: self.store.addCreator)

            if !self.store.state.data.notes.isEmpty || self.isEditing {
                NotesSection(notes: self.store.state.data.notes,
                             isEditing: self.isEditing,
                             deleteAction: self.store.deleteNotes,
                             addAction: self.store.addNote,
                             editAction: self.store.editNote)
            }

            TagsSection(tags: self.store.state.data.tags)

            if !self.store.state.data.attachments.isEmpty || self.isEditing {
                AttachmentsSection(attachments: self.store.state.data.attachments,
                                   isEditing: self.isEditing)
            }
        }
        .navigationBarItems(trailing:
            HStack {
                if self.isEditing {
                    Button(action: {
                        self.store.cancelChanges()
                        self.editMode?.wrappedValue = .inactive
                    }) {
                        Text("Cancel")
                    }
                }
                Button(action: {
                    if self.isEditing {
                        self.store.saveChanges()
                    } else {
                        self.store.startEditing()
                    }
                    self.editMode?.wrappedValue.toggle()
                }) {
                    Text(self.isEditing ? "Done" : "Edit")
                }
            }
        )
        .navigationBarBackButtonHidden(self.isEditing)
        // SWIFTUI BUG: - somehow assign binding note to NoteEditingView
        .sheet(item: self.$store.state.presentedNote, onDismiss: {
            self.store.state.presentedNote = nil
        }, content: { note in
            NoteEditingView(note: note, saveAction: self.store.saveNote)
        })
    }
}

fileprivate extension EditMode {
    mutating func toggle() {
        self = self == .active ? .inactive : .active
    }
}

fileprivate struct FieldsSection: View {
    let type: String
    let visibleFields: [String]
    @Binding var fields: [String: NewItemDetailStore.StoreState.Field]
    @Binding var creators: [NewItemDetailStore.StoreState.Creator]
    @Binding var abstract: String?
    let isEditing: Bool

    let deleteCreators: (IndexSet) -> Void
    let moveCreators: (IndexSet, Int) -> Void
    let addCreator: () -> Void

    var body: some View {
        Section {
            ItemDetailFieldView(title: "Item Type", value: .constant(self.type), editingEnabled: false)

            ForEach(self.creators) { creator in
                // SWIFTUI BUG: - create a bindable instance of creator somehow, when using
                // ForEach(0..<self.creators.count) we get a crash after onDelete because
                // the index gets out of sync with the array
                ItemDetailCreatorView(creator: .constant(creator),
                                      editingEnabled: self.isEditing)
            }.onDelete(perform: self.deleteCreators)
             .onMove(perform: self.moveCreators)
            if self.isEditing {
                ItemDetailAddView(title: "Add author", action: self.addCreator)
            }

            ForEach(self.visibleFields, id: \.self) { key in
                Binding(self.$fields[key]).flatMap {
                    ItemDetailFieldView(title: $0.wrappedValue.name,
                                        value: $0.value,
                                        editingEnabled: self.isEditing)
                }
            }

            if self.isEditing || !(self.abstract?.isEmpty ?? true) {
                Binding(self.$abstract).flatMap { ItemDetailAbstractView(abstract: $0, isEditing: self.isEditing) }
            }
        }
    }
}

fileprivate struct NotesSection: View {
    let notes: [NewItemDetailStore.StoreState.Note]
    let isEditing: Bool

    let deleteAction: (IndexSet) -> Void
    let addAction: () -> Void
    let editAction: (NewItemDetailStore.StoreState.Note) -> Void

    var body: some View {
        Section {
            ItemDetailSectionView(title: "Notes")
            ForEach(self.notes) { note in
                // SWIFTUI BUG: - Button action in cell not called
                Button(action: {
                    self.editAction(note)
                }) {
                    ItemDetailNoteView(text: note.title)
                }.onTapGesture {
                    self.editAction(note)
                }
            }.onDelete(perform: self.deleteAction)
            if self.isEditing {
                ItemDetailAddView(title: "Add note", action: self.addAction)
            }
        }
    }
}

fileprivate struct TagsSection: View {
    let tags: [NewItemDetailStore.StoreState.Tag]

    var body: some View {
        Section {
            ItemDetailSectionView(title: "Tags")
            ForEach(self.tags) { tag in
                ItemDetailTagView(color: tag.uiColor.flatMap(Color.init), name: tag.name)
            }.onDelete(perform: self.delete)
            ItemDetailAddView(title: "Add tag", action: {})
        }
    }

    private func delete(at offsets: IndexSet) {

    }
}

fileprivate struct AttachmentsSection: View {
    let attachments: [NewItemDetailStore.StoreState.Attachment]
    let isEditing: Bool

    var body: some View {
        Section {
            ItemDetailSectionView(title: "Attachments")
            ForEach(self.attachments) { attachment in
                ItemDetailAttachmentView(filename: attachment.filename)
            }.onDelete(perform: self.delete)
            if self.isEditing {
                ItemDetailAddView(title: "Add attachment", action: {})
            }
        }
    }

    private func delete(at offsets: IndexSet) {

    }
}

#if DEBUG

struct ItemDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let controllers = Controllers()
        let userId = 23//try! controllers.dbStorage.createCoordinator().perform(request: ReadUserDbRequest()).identifier
        let store = try! NewItemDetailStore(type: .creation(libraryId: .custom(.myLibrary),
                                                            collectionKey: nil, filesEditable: true),
                                            userId: userId,
                                            apiClient: controllers.apiClient,
                                            fileStorage: controllers.fileStorage,
                                            dbStorage: controllers.dbStorage,
                                            schemaController: controllers.schemaController)
        return ItemDetailView(store: store)
    }
}

#endif
