//
//  ItemSortingView.swift
//  Zotero
//
//  Created by Michal Rentka on 29.06.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemSortingView: View {
    @State var sortType: ItemsSortType

    let changed: (ItemsSortType) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Picker(L10n.Items.sortOrder, selection: $sortType.ascending) {
                Text("Ascending").tag(true)
                Text("Descending").tag(false)
            }
            .pickerStyle(.segmented)
            .padding(EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20))

            List {
                ForEach(ItemsSortType.Field.allCases) { field in
                    Button {
                        var new = sortType
                        new.field = field
                        new.ascending = field.defaultOrderAscending // 🍎 check if change flips UI
                        sortType = new
                    } label: {
                        SortTypeRow(title: field.title, isSelected: (sortType.field == field))
                    }
                    .foregroundColor(Color(.label))
                }
            }
            .listStyle(.plain)
        }
        .navigationBarTitle(Text(L10n.Items.sortBy), displayMode: .inline)
        .onChange(of: sortType) { newValue in
            self.changed(newValue)
        }
    }
}

private struct SortTypeRow: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        HStack {
            Text(self.title)
            if self.isSelected {
                Spacer()
                Image(systemName: "checkmark")
                    .foregroundColor(Asset.Colors.zoteroBlue.swiftUiColor)
            }
        }
    }
}
