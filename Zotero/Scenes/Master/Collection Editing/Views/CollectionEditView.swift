//
//  CollectionEditView.swift
//  Zotero
//
//  Created by Michal Rentka on 24/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct CollectionEditView: View {
    @EnvironmentObject var viewModel: ViewModel<CollectionEditActionHandler>

    weak var coordinatorDelegate: CollectionEditingCoordinatorDelegate?

    private var title: Text {
        return Text(self.viewModel.state.key == nil ? L10n.Collections.createTitle : L10n.Collections.editTitle)
    }

    var body: some View {
        Form {
            Section {
                TextField(L10n.name, text: self.viewModel.binding(keyPath: \.name, action: { .setName($0) }))
            }

            Section {
                Button(action: {
                    self.showPickerView()
                }) {
                    HStack {
                        Image(uiImage: self.viewModel.state.parent == nil ?
                                        Asset.Images.Cells.library.image :
                                        Asset.Images.Cells.collection.image)
                            .renderingMode(.template)
                            .foregroundColor(Asset.Colors.zoteroBlue.swiftUiColor)
                        Text(self.viewModel.state.parent?.name ?? self.viewModel.state.library.name)
                            .foregroundColor(.primary)
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
                        Text(L10n.Collections.delete)
                            .foregroundColor(Color.red)
                    }
                    Button(action: {
                        self.viewModel.process(action: .deleteWithItems)
                    }) {
                        Text(L10n.Collections.deleteWithItems)
                            .foregroundColor(Color.red)
                    }
                }
            }

            if self.viewModel.state.shouldDismiss {
                Text("").onAppear {
                    self.coordinatorDelegate?.dismiss()
                }
            }
        }
        .navigationBarItems(leading: self.leadingItems, trailing: self.trailingItems)
        .navigationBarTitle(self.title, displayMode: .inline)
        .alert(item: self.viewModel.binding(keyPath: \.error, action: { .setError($0) })) { error -> Alert in
            return Alert(title: Text(L10n.error), message: Text(error.localizedDescription))
        }
        .disabled(self.viewModel.state.loading)
    }

    private var leadingItems: some View {
        Button(action: {
            self.coordinatorDelegate?.dismiss()
        }, label: {
            Text(L10n.cancel)
                .padding(.vertical, 10)
                .padding(.trailing, 10)
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
                    Text(L10n.save)
                        .padding(.vertical, 10)
                        .padding(.leading, 10)
                }
            }
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
