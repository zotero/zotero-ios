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

            if !self.store.state.data.tags.isEmpty || self.isEditing {
                TagsSection(tags: self.store.state.data.tags,
                            isEditing: self.isEditing,
                            addAction: {
                                self.store.state.showTagPicker = true
                            },
                            deleteAction: self.store.deleteTags)
            }

            if !self.store.state.data.attachments.isEmpty || self.isEditing {
                AttachmentsSection(attachments: self.store.state.data.attachments,
                                   downloadProgress: self.store.state.downloadProgress,
                                   downloadError: self.store.state.downloadError,
                                   isEditing: self.isEditing,
                                   tapAction: { attachment in
                                       if !self.isEditing {
                                          self.store.openAttachment(attachment)
                                       }
                                   },
                                   deleteAction: self.store.deleteAttachments)
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
        .betterSheet(item: self.$store.state.presentedNote,
               onDismiss: {
                   self.store.state.presentedNote = nil
               },
               content: { note in
                   NoteEditingView(note: note, saveAction: self.store.saveNote)
               })
        .betterSheet(isPresented: self.$store.state.showTagPicker,
               onDismiss: {
                   self.store.state.showTagPicker = false
               },
               content: {
                   TagPickerView(store: TagPickerStore(libraryId: self.store.state.libraryId,
                                                       selectedTags: Set(self.store.state.data.tags.map({ $0.id })),
                                                       dbStorage: self.store.dbStorage),
                                 saveAction: self.store.setTags)
               })
        .betterSheet(item: self.$store.state.pdfAttachment,
               onDismiss: {
                   self.store.state.pdfAttachment = nil
               },
               content: { url in
                   PdfReaderView(url: url)
               })
        .betterSheet(item: self.$store.state.webAttachment,
               onDismiss: {
                   self.store.state.webAttachment = nil
               },
               content: { url in
                   SafariView(url: url)
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

fileprivate struct FieldsSection: View {
    let type: String
    let visibleFields: [String]
    @Binding var fields: [String: ItemDetailStore.State.Field]
    @Binding var creators: [ItemDetailStore.State.Creator]
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
    let notes: [ItemDetailStore.State.Note]
    let isEditing: Bool

    let deleteAction: (IndexSet) -> Void
    let addAction: () -> Void
    let editAction: (ItemDetailStore.State.Note) -> Void

    var body: some View {
        Section {
            ItemDetailSectionView(title: "Notes")
            ForEach(self.notes) { note in
                // SWIFTUI BUG: - Button action in cell not called in EditMode.active
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
    let tags: [Tag]
    let isEditing: Bool

    let addAction: () -> Void
    let deleteAction: (IndexSet) -> Void

    var body: some View {
        Section {
            ItemDetailSectionView(title: "Tags")
            ForEach(self.tags) { tag in
                TagView(color: .init(hex: tag.color), name: tag.name)
            }.onDelete(perform: self.deleteAction)
            if self.isEditing {
                ItemDetailAddView(title: "Add tag", action: self.addAction)
            }
        }
    }
}

fileprivate struct AttachmentsSection: View {
    let attachments: [ItemDetailStore.State.Attachment]
    let downloadProgress: [String: Double]
    let downloadError: [String: Error]
    let isEditing: Bool

    let tapAction: (ItemDetailStore.State.Attachment) -> Void
    let deleteAction: (IndexSet) -> Void

    var body: some View {
        Section {
            ItemDetailSectionView(title: "Attachments")
            ForEach(self.attachments) { attachment in
                // SWIFTUI BUG: - Button action in cell not called in EditMode.active
                Button(action: {
                    self.tapAction(attachment)
                }) {
                    ItemDetailAttachmentView(title: attachment.title,
                                             rightAccessory: self.accessory(for: attachment,
                                                                            progress: self.downloadProgress[attachment.key],
                                                                            error: self.downloadError[attachment.key]),
                                             progress: self.downloadProgress[attachment.key])
                }.onTapGesture {
                    self.tapAction(attachment)
                }
            }.onDelete(perform: self.deleteAction)
            if self.isEditing {
                ItemDetailAddView(title: "Add attachment", action: {})
            }
        }
    }

    private func accessory(for attachment: ItemDetailStore.State.Attachment,
                           progress: Double?, error: Error?) -> AccessoryView.Accessory {
        if error != nil {
            return .error
        }

        if progress != nil {
            return .progress
        }

        switch attachment.type {
        case .file(_, _, let isLocal):
            return isLocal ? .disclosureIndicator : .downloadIcon
        case .url:
            return .disclosureIndicator
        }
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
