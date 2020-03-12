//
//  CollectionEditView.swift
//  Zotero
//
//  Created by Michal Rentka on 24/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct CollectionEditView: View {
    @EnvironmentObject private(set) var viewModel: ViewModel<CollectionEditActionHandler>

    weak var coordinatorDelegate: (CollectionEditingCoordinatorDelegate & Coordinator)?

    private var title: Text {
        return Text(self.viewModel.state.key == nil ? "Create collection" : "Edit collection")
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: self.viewModel.binding(keyPath: \.name, action: { .setName($0) }))
            }

            Section {
                Button(action: {
                    self.showPickerView()
                }) {
                    HStack {
                        Image(self.viewModel.state.parent == nil ?
                                "icon_cell_library" :
                                "icon_cell_collection")
                            .renderingMode(.template)
                            .foregroundColor(.blue)
                        Text(self.viewModel.state.parent?.name ?? self.viewModel.state.library.name)
                            .foregroundColor(.black)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundColor(.gray)
                    }
                }
            }

            if self.viewModel.state.key != nil {
                Section {
                    Button(action: {
                        self.viewModel.process(action: .delete)
                    }) {
                        Text("Delete Collection")
                            .foregroundColor(Color.red)
                    }
                    Button(action: {
                        self.viewModel.process(action: .deleteWithItems)
                    }) {
                        Text("Delete Collection and Items")
                            .foregroundColor(Color.red)
                    }
                }
            }

            if self.viewModel.state.shouldDismiss {
                EmptyView().onAppear {
                    self.coordinatorDelegate?.dismiss()
                }
            }
        }
        .navigationBarItems(leading: self.leadingItems, trailing: self.trailingItems)
        .navigationBarTitle(self.title, displayMode: .inline)
        .alert(item: self.viewModel.binding(keyPath: \.error, action: { .setError($0) })) { error -> Alert in
            return Alert(title: Text("Error"), message: Text(self.message(for: error)))
        }
        .disabled(self.viewModel.state.loading)
    }

    private var leadingItems: some View {
        Button(action: {
            self.coordinatorDelegate?.dismiss()
        }, label: {
            Text("Cancel")
        })
    }

    private var trailingItems: some View {
        Group {
            if self.viewModel.state.loading {
                ActivityIndicatorView(style: .medium, isAnimating: .constant(true))
            } else {
                Button(action: {
                    self.viewModel.process(action: .save)
                }) {
                    Text("Save")
                }
            }
        }
    }

    private func message(for error: CollectionEditError) -> String {
        switch error {
        case .emptyName:
            return "You have to fill the name"
        case .saveFailed:
            return "Could not save collection '\(self.viewModel.state.name)'. Try again."
        }
    }

    private func showPickerView() {
        self.coordinatorDelegate?.showCollectionPicker(viewModel: self.viewModel)
    }
}

struct CollectionEditView_Previews: PreviewProvider {
    static var previews: some View {
        let state = CollectionEditState(library: .init(identifier: .custom(.myLibrary),
                                                       name: "My Librrary",
                                                       metadataEditable: true,
                                                       filesEditable: true),
                                        key: nil,
                                        name: "",
                                        parent: nil)
        let handler = CollectionEditActionHandler(dbStorage: Controllers().userControllers!.dbStorage)
        return CollectionEditView()
                        .environmentObject(ViewModel(initialState: state, handler: handler))
    }
}
