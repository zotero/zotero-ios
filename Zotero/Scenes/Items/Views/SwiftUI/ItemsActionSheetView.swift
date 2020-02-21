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
        case dismiss,
        startEditing,
        showSortTypePicker,
        toggleSortOrder,
        showItemCreation,
        showNoteCreation,
        showAttachmentPicker
    }

    @State var sortType: ItemsSortType

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
                        self.actionObserver.send(.startEditing)
                    }) {
                        Text("Select Items")
                    }

                    Divider()

                    Button(action: {
                        self.actionObserver.send(.showSortTypePicker)
                    }) {
                        Text("Sort By: \(self.sortType.field.title)")
                    }

                    Button(action: {
                        self.sortType.ascending.toggle()
                        self.actionObserver.send(.toggleSortOrder)
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
                .padding(.top, 74)
            }
        }
        .edgesIgnoringSafeArea(.all)
    }

    private var sortOrderTitle: String {
        return self.sortType.ascending ? "Ascending" : "Descending"
    }
}

struct ItemsActionSheetView_Previews: PreviewProvider {
    static var previews: some View {
        ItemsActionSheetView(sortType: .default)
    }
}
