//
//  CollectionsPickerView.swift
//  Zotero
//
//  Created by Michal Rentka on 11/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct CollectionsPickerView: View {
    @EnvironmentObject private(set) var viewModel: ViewModel<CollectionPickerActionHandler>

    private(set) var selectedKeys: (Set<String>) -> Void
    let closeAction: () -> Void

    var body: some View {
        List(selection: self.viewModel.binding(keyPath: \.selected, action: { .setSelected($0) })) {
            ForEach(self.viewModel.state.collections) { collection in
                CollectionRow(data: collection)
                    .listRowInsets(EdgeInsets(top: 0,
                                              leading: self.inset(for: collection.level),
                                              bottom: 0,
                                              trailing: 0))
            }
        }
        .navigationBarTitle(Text(self.navBarTitle), displayMode: .inline)
        .navigationBarItems(leading:
                                Button(action: self.closeAction,
                                       label: { Text("Cancel") })
                            , trailing:
                                Button(action: {
                                    self.selectedKeys(self.viewModel.state.selected)
                                    self.closeAction()
                                },
                                label: {
                                    Text("Save")
                                })
        )
        .environment(\.editMode, .constant(.active))
    }

    private var navBarTitle: String {
        switch self.viewModel.state.selected.count {
        case 0:
            return "Select a Collection"
        case 1:
            return "1 Collection Selected"
        default:
            return "\(self.viewModel.state.selected.count) Collections Selected"
        }
    }

    private func inset(for level: Int) -> CGFloat {
        return CollectionRow.levelOffset + (CGFloat(level) * CollectionRow.levelOffset)
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
        return CollectionsPickerView(selectedKeys: { _ in }, closeAction: {})
                                .environmentObject(ViewModel(initialState: state, handler: handler))
    }
}
