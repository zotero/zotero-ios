//
//  ItemSortTypePickerView.swift
//  Zotero
//
//  Created by Michal Rentka on 11/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemSortTypePickerView: View {
    @Binding var sortBy: ItemsSortType.Field

    let closeAction: () -> Void

    var body: some View {
        List {
            ForEach(ItemsSortType.Field.allCases) { sortType in
                Button(action: {
                    self.sortBy = sortType
                    self.closeAction()
                }) {
                    SortTypeRow(title: sortType.title,
                                isSelected: (self.sortBy == sortType))
                }
                .foregroundColor(Color(.label))
            }
        }
        .navigationBarTitle(Text(L10n.Items.sortBy), displayMode: .inline)
        .padding(EdgeInsets(top: 1, leading: 0, bottom: 0, trailing: 0))
        .background(Color(UIColor.systemGroupedBackground))
    }
}

fileprivate struct SortTypeRow: View {
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

struct ItemSortTypePickerView_Previews: PreviewProvider {
    static var previews: some View {
        ItemSortTypePickerView(sortBy: .constant(.title), closeAction: {})
    }
}
