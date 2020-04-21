//
//  CollectionPickerView.swift
//  Zotero
//
//  Created by Michal Rentka on 24/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct CollectionPickerView: View {
    @EnvironmentObject var viewModel: ViewModel<CollectionPickerActionHandler>

    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>

    let saveAction: (Collection?) -> Void

    var body: some View {
        List {
            Button(action: {
                self.saveAction(nil)
                self.presentationMode.wrappedValue.dismiss()
            }) {
                HStack {
                    LibraryRow(title: self.viewModel.state.library.name)
                    if self.viewModel.state.selected.contains(self.viewModel.state.library.name) {
                        Spacer()
                        Image(systemName: "checkmark")
                    }
                }
            }

            ForEach(self.viewModel.state.collections) { collection in
                Button(action: {
                    self.saveAction(collection)
                    self.presentationMode.wrappedValue.dismiss()
                }) {
                    HStack {
                        CollectionRow(data: collection)
                        if self.viewModel.state.selected.contains(collection.key) {
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
        .navigationBarTitle(Text(L10n.Collections.pickerTitle))
    }

    private func inset(for level: Int) -> CGFloat {
        return CollectionRow.levelOffset + (CGFloat(level) * CollectionRow.levelOffset)
    }
}

struct CollectionPickerView_Previews: PreviewProvider {
    static var previews: some View {
        let state = CollectionPickerState(library: .init(identifier: .custom(.myLibrary),
                                                         name: "My Library",
                                                         metadataEditable: true,
                                                         filesEditable: true),
                                          excludedKeys: [],
                                          selected: ["My Library"])
        let handler = CollectionPickerActionHandler(dbStorage: Controllers().userControllers!.dbStorage)
        return CollectionPickerView() { _ in }
                        .environmentObject(ViewModel(initialState: state, handler: handler))
    }
}
