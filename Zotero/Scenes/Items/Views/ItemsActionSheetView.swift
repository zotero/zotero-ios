//
//  ItemsActionSheetView.swift
//  Zotero
//
//  Created by Michal Rentka on 21/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import SwiftUI

struct ItemsActionSheetView: View {
    enum Action {
        case dismiss
        case showSortTypePicker
        case showItemCreation
        case showNoteCreation
        case showAttachmentPicker
    }

    @EnvironmentObject private(set) var viewModel: ViewModel<ItemsActionHandler>

    let actionObserver = PassthroughSubject<Action, Never>()

    var body: some View {
        Group {
            ZStack(alignment: .topTrailing) {
                Color.black.opacity(0.1)
                    .onTapGesture {
                        self.actionObserver.send(.dismiss)
                    }

                VStack(alignment: .leading, spacing: 18) {
                    Button(action: {
                        self.viewModel.process(action: .startEditing)
                        self.actionObserver.send(.dismiss)
                    }) {
                        Text("Select Items")
                    }

                    Divider()

                    Button(action: {
                        self.actionObserver.send(.showSortTypePicker)
                    }) {
                        Text("Sort By: \(self.viewModel.state.sortType.field.title)")
                    }

                    Button(action: {
                        self.viewModel.process(action: .toggleSortOrder)
                    }) {
                        Text("Sort Order: \(self.sortOrderTitle)")
                    }

                    Divider()

                    Button(action: {
                        self.actionObserver.send(.showItemCreation)
                    }) {
                        Text("New Item")
                    }

                    Button(action: {
                        self.actionObserver.send(.showNoteCreation)
                    }) {
                        Text("New Standalone Note")
                    }

                    Button(action: {
                        self.actionObserver.send(.showAttachmentPicker)
                    }) {
                        Text("Upload File")
                    }
                }
                .padding()
                .frame(width: 260, alignment: .trailing)
                .background(Color.white)
                .padding(.top, 130)
            }
        }
        .edgesIgnoringSafeArea(.all)
    }

    private var sortOrderTitle: String {
        return self.viewModel.state.sortType.ascending ? "Ascending" : "Descending"
    }
}

struct ItemsActionSheetView_Previews: PreviewProvider {
    static var previews: some View {
        let state = ItemsState(type: .all,
                               library: .init(identifier: .custom(.myLibrary),
                                              name: "My Library",
                                              metadataEditable: true,
                                              filesEditable: true),
                               results: nil,
                               sortType: .default,
                               error: nil)
        let controllers = Controllers()
        let handler = ItemsActionHandler(dbStorage: controllers.userControllers!.dbStorage,
                                         fileStorage: controllers.fileStorage,
                                         schemaController: controllers.schemaController)
        return ItemsActionSheetView()
                    .environmentObject(ViewModel(initialState: state, handler: handler))
    }
}
