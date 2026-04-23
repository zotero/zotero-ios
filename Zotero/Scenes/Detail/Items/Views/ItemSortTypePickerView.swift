//
//  ItemSortTypePickerView.swift
//  Zotero
//
//  Created by Michal Rentka on 11/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemSortTypePickerView: View {
    @Binding var sortType: ItemsSortType

    let closeAction: () -> Void

    var body: some View {
        List {
            ForEach(ItemsSortType.Field.allCases) { field in
                Button {
                    var new = sortType
                    new.field = field
                    new.ascending = field.defaultOrderAscending
                    sortType = new
                    self.closeAction()
                } label: {
                    SortTypeRow(title: field.title, isSelected: (sortType.field == field))
                }
                .foregroundColor(Color(.label))
            }
        }
        .navigationBarTitle(Text(L10n.Items.sortBy), displayMode: .inline)
        .padding(EdgeInsets(top: 1, leading: 0, bottom: 0, trailing: 0))
        .background(Color(UIColor.systemGroupedBackground))
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

struct ItemSortTypePickerView_Previews: PreviewProvider {
    static var previews: some View {
        ItemSortTypePickerView(sortType: .constant(ItemsSortType(field: .creator, ascending: false)), closeAction: {})
    }
}
