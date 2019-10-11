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

    @Environment(\.presentationMode) private var presentationMode: Binding<PresentationMode>

    var body: some View {
        List {
            ForEach(ItemsSortType.Field.allCases) { sortType in
                SortTypeRow(title: sortType.title,
                            isSelected: (self.sortBy == sortType))
                    .onTapGesture {
                        self.sortBy = sortType
                        self.presentationMode.wrappedValue.dismiss()
                    }
            }
        }
        .navigationBarTitle(Text("Sort By"), displayMode: .inline)
        .navigationBarItems(leading: Button(action: { self.presentationMode.wrappedValue.dismiss() },
                                            label: { Text("Cancel") }))
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
                    .foregroundColor(.blue)
            }
        }
    }
}

struct ItemSortTypePickerView_Previews: PreviewProvider {
    static var previews: some View {
        ItemSortTypePickerView(sortBy: .constant(.title))
    }
}
