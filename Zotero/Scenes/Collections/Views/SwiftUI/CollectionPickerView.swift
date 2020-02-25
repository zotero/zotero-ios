//
//  CollectionPickerView.swift
//  Zotero
//
//  Created by Michal Rentka on 24/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct CollectionPickerView: View {
    @EnvironmentObject private(set) var store: CollectionPickerStore

    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>

    @Binding var collection: Collection?

    var body: some View {
        List {
            Button(action: {
                self.collection = nil
                self.presentationMode.wrappedValue.dismiss()
            }) {
                HStack {
                    LibraryRow(title: self.store.state.library.name)
                    if self.collection == nil {
                        Spacer()
                        Image(systemName: "checkmark")
                    }
                }
            }

            ForEach(self.store.state.collections) { collection in
                Button(action: {
                    self.collection = collection
                    self.presentationMode.wrappedValue.dismiss()
                }) {
                    HStack {
                        CollectionRow(data: collection)
                        if self.collection == collection {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                    .padding(.trailing, 20)
                }
                .listRowInsets(EdgeInsets(top: 0,
                                          leading: self.inset(for: collection.level),
                                          bottom: 0,
                                          trailing: 0))
            }
        }
        .navigationBarTitle(Text("Pick parent"))
    }

    private func inset(for level: Int) -> CGFloat {
        return CollectionRow.levelOffset + (CGFloat(level) * CollectionRow.levelOffset)
    }
}

struct CollectionPickerView_Previews: PreviewProvider {
    static var previews: some View {
        CollectionPickerView(collection: .constant(nil))
                .environmentObject(CollectionPickerStore(library: .init(identifier: .custom(.myLibrary),
                                                                           name: "My Library",
                                                                           metadataEditable: true,
                                                                           filesEditable: true),
                                                         excludedKeys: [],
                                                         dbStorage: Controllers().userControllers!.dbStorage))
    }
}
