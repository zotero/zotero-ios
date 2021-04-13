//
//  CollectionsPickerView.swift
//  Zotero
//
//  Created by Michal Rentka on 11/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct CollectionsPickerView: View {
    @EnvironmentObject var viewModel: ViewModel<CollectionPickerActionHandler>

    let completionAction: (Set<String>) -> Void
    let closeAction: () -> Void

    var body: some View {
        List {
            ForEach(self.viewModel.state.collections) { collection in
                Button(action: {
                    if let key = collection.identifier.key {
                        self.viewModel.process(action: .toggleSelection(key))
                    }
                }) {
                    SelectableCollectionRow(collection: collection, selected: self.isSelected(collection: collection))
                }
                .buttonStyle(BorderlessButtonStyle())
                .listRowInsets(EdgeInsets(top: 0, leading: self.inset(for: collection.level), bottom: 0, trailing: 0))
            }
        }
        .animation(.none)
        .navigationBarTitle(Text(self.navBarTitle), displayMode: .inline)
        .navigationBarItems(leading:
                                Button(action: self.closeAction,
                                       label: {
                                           Text(L10n.cancel)
                                              .padding(.vertical, 10)
                                              .padding(.trailing, 10)
                                       })
                            , trailing:
                                Button(action: {
                                    self.completionAction(self.viewModel.state.selected)
                                    self.closeAction()
                                },
                                label: {
                                    Text(L10n.add)
                                        .padding(.vertical, 10)
                                        .padding(.leading, 10)
                                })
        )
    }

    private var navBarTitle: String {
        switch self.viewModel.state.selected.count {
        case 0:
            return L10n.Items.zeroCollectionsSelected
        case 1:
            return L10n.Items.oneCollectionsSelected
        default:
            return L10n.Items.manyCollectionsSelected(self.viewModel.state.selected.count)
        }
    }

    private func inset(for level: Int) -> CGFloat {
        return CollectionRow.levelOffset + (CGFloat(level) * CollectionRow.levelOffset)
    }

    private func isSelected(collection: Collection) -> Bool {
        guard let key = collection.identifier.key else { return false }
        return self.viewModel.state.selected.contains(key)
    }
}

fileprivate struct SelectableCollectionRow: View {
    let collection: Collection
    let selected: Bool

    var body: some View {
        HStack {
            CollectionRow(data: self.collection)

            Spacer().frame(minWidth: 8)

            if self.selected {
                Image(systemName: "checkmark")
                    .foregroundColor(Asset.Colors.zoteroBlue.swiftUiColor)
                    .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 12))
            }
        }
    }
}

struct CollectionsPickerView_Previews: PreviewProvider {
    static var previews: some View {
        let state = CollectionPickerState(library: .init(identifier: .custom(.myLibrary),
                                                         name: "My Library",
                                                         metadataEditable: true,
                                                         filesEditable: true),
                                          excludedKeys: [],
                                          selected: ["My Library"])
        let handler = CollectionPickerActionHandler(dbStorage: Controllers().userControllers!.dbStorage)
        return CollectionsPickerView(completionAction: { _ in }, closeAction: {})
                                .environmentObject(ViewModel(initialState: state, handler: handler))
    }
}
