//
//  ItemsActionSheetView.swift
//  Zotero
//
//  Created by Michal Rentka on 21/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemsActionSheetView: View {
    @EnvironmentObject private(set) var store: ItemsStore

    var startEditing: (() -> Void)?
    var showItemCreation: (() -> Void)?
    var dismiss: (() -> Void)?

    var body: some View {
        Group {
            ZStack(alignment: .topTrailing) {
                Color.black.opacity(0.1)
                    .onTapGesture {
                        self.dismiss?()
                    }

                VStack(alignment: .leading, spacing: 12) {
                    Button(action: {
                        self.startEditing?()
                        self.dismiss?()
                    }) {
                        Text("Select Items")
                    }

                    Divider()

                    Button(action: {
                        NotificationCenter.default.post(name: .presentSortTypePicker, object: self.$store.state.sortType.field)
                        self.dismiss?()
                    }) {
                        Text("Sort By: \(self.store.state.sortType.field.title)")
                    }

                    Button(action: { self.store.state.sortType.ascending.toggle() }) {
                        Text("Sort Order: \(self.sortOrderTitle)")
                    }

                    Divider()

                    Button(action: {
                        self.dismiss?()
                        self.showItemCreation?()
                    }) {
                        Text("New Item")
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
        return self.store.state.sortType.ascending ? "Ascending" : "Descending"
    }
}

struct ItemsActionSheetView_Previews: PreviewProvider {
    static var previews: some View {
        ItemsActionSheetView()
    }
}
