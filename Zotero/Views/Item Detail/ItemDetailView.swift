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

    var body: some View {
        List {
            FieldsSection(title: self.store.state.data.title,
                          fields: self.store.state.data.fields.filter({ !$0.value.isEmpty }),
                          abstract: self.store.state.data.abstract)

            if !self.store.state.data.notes.isEmpty {
                NotesSection(notes: self.store.state.data.notes)
            }

            if !self.store.state.data.tags.isEmpty {
                TagsSection(tags: self.store.state.data.tags)
            }

            if !self.store.state.data.attachments.isEmpty {
                AttachmentsSection(attachments: self.store.state.data.attachments)
            }
        }
    }
}

fileprivate struct FieldsSection: View {
    let title: String
    let fields: [NewItemDetailStore.StoreState.Field]
    let abstract: String?

    var body: some View {
        Section {
            ItemDetailTitleView(title: self.title)
            ForEach(self.fields) { field in
                ItemDetailFieldView(field: field)
            }
            self.abstract.flatMap(ItemDetailAbstractView.init)
        }
    }
}

fileprivate struct NotesSection: View {
    let notes: [NewItemDetailStore.StoreState.Note]

    var body: some View {
        Section {
            ItemDetailTitleView(title: "Notes")
                // SWIFTUI BUG: - this doesn't work if specified in the child view, move to child when possible
                .listRowBackground(Color.gray.opacity(0.15))
            ForEach(self.notes) { note in
                ItemDetailNoteView(text: note.title)
            }
        }
    }
}

fileprivate struct TagsSection: View {
    let tags: [NewItemDetailStore.StoreState.Tag]

    var body: some View {
        Section {
            ItemDetailTitleView(title: "Tags")
                // SWIFTUI BUG: - this doesn't work if specified in the child view, move to child when possible
                .listRowBackground(Color.gray.opacity(0.15))
            ForEach(self.tags) { tag in
                ItemDetailTagView(color: tag.uiColor.flatMap(Color.init), name: tag.name)
            }
        }
    }
}

fileprivate struct AttachmentsSection: View {
    let attachments: [NewItemDetailStore.StoreState.Attachment]

    var body: some View {
        Section {
            ItemDetailTitleView(title: "Attachments")
                // SWIFTUI BUG: - this doesn't work if specified in the child view, move to child when possible
                .listRowBackground(Color.gray.opacity(0.15))
        }
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
