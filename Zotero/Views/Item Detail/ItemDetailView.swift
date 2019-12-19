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
    @Environment(\.editMode) private var editMode: Binding<EditMode>?
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
        .alert(item: self.$store.state.error) { error -> Alert in
            switch error {
            case .droppedFields(let names):
                return Alert(title: Text("Change Item Type"),
                             message: Text(self.changeItemTypeMessage(for: names)),
                             primaryButton: .default(Text("Ok"), action: self.store.acceptPromptSnapshot),
                             secondaryButton: .cancel(self.store.cancelPromptSnapshot))
            case .fileNotCopied(let count):
            return Alert(title: Text("Error"),
                         message: Text(self.fileCopyMessage(count: count)),
                         dismissButton: .cancel(Text("Ok")))
            default:
                return Alert(title: Text("Error"), message: Text("Unknown error"), dismissButton: .cancel())
            }
        }
    }

    private func fileCopyMessage(count: Int) -> String {
        if count == 1 {
            return "Could not create attachment"
        }
        return "Could not create \(count) attachments"
    }

    private func changeItemTypeMessage(for names: [String]) -> String {
        let formattedNames = names.map({ "- \($0)\n" }).joined()
        return """
               Are you sure you want to change the item type?

               The following fields will be lost:

               \(formattedNames)
               """
    }

    private var trailingNavbarItems: some View {
        HStack {
            if self.editMode?.wrappedValue.isEditing == true {
                Button(action: {
                    self.store.cancelChanges()
                    if self.store.state.type.isCreation {
                        self.presentationMode.wrappedValue.dismiss()
                    } else {
                        self.editMode?.wrappedValue = .inactive
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

struct ItemDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let controllers = Controllers()
        controllers.schemaController.reloadSchemaIfNeeded()
        let store = ItemDetailStore(type: .creation(libraryId: .custom(.myLibrary),
                                                    collectionKey: nil, filesEditable: true),
                                    userId: Defaults.shared.userId,
                                    apiClient: controllers.apiClient,
                                    fileStorage: controllers.fileStorage,
                                    dbStorage: controllers.userControllers!.dbStorage,
                                    schemaController: controllers.schemaController)

        return ItemDetailView()
                    .environment(\.editMode, .constant(.active))
                    .environmentObject(store)
    }
}
