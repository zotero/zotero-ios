//
//  ItemSortingView.swift
//  Zotero
//
//  Created by Michal Rentka on 29.06.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

final class ItemSortingObserver: ObservableObject {
    @Published var showExpandedPicker: Bool

    init(showExpandedPicker: Bool) {
        self.showExpandedPicker = showExpandedPicker
    }
}

struct ItemSortingView: View {
    @ObservedObject var observer: ItemSortingObserver
    @State var sortType: ItemsSortType

    let changed: (ItemsSortType) -> Void
    let showPicker: (ItemSortTypePickerView) -> Void
    let closePicker: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            if observer.showExpandedPicker {
                inlineSortTypePicker
            } else {
                sortTypeButton
            }

            Divider()

            Picker(L10n.Items.sortOrder, selection: $sortType.ascending) {
                Text("Ascending").tag(true)
                Text("Descending").tag(false)
            }
            .pickerStyle(.segmented)
            .padding(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))

            if observer.showExpandedPicker {
                Spacer()
            }
        }
        .padding(EdgeInsets(top: 20, leading: 0, bottom: 20, trailing: 0))
        .onChange(of: sortType) { newValue in
            self.changed(newValue)
        }
    }

    private var sortTypeButton: some View {
        Button {
            showPicker(ItemSortTypePickerView(sortType: $sortType, closeAction: closePicker))
        } label: {
            HStack {
                Text("\(L10n.Items.sortBy): \(sortType.field.title)")
                    .foregroundColor(Color(UIColor.label))

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(Color(UIColor.systemGray2))
                    .font(.body.weight(.semibold))
                    .imageScale(.small)
            }
        }
        .padding(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
    }

    private var inlineSortTypePicker: some View {
        VStack(spacing: 0) {
            ForEach(ItemsSortType.Field.allCases) { field in
                Button {
                    var new = sortType
                    new.field = field
                    new.ascending = field.defaultOrderAscending
                    sortType = new
                } label: {
                    HStack {
                        Text(field.title)
                            .foregroundColor(Color(.label))

                        Spacer()

                        if sortType.field == field {
                            Image(systemName: "checkmark")
                                .foregroundColor(Asset.Colors.zoteroBlue.swiftUiColor)
                        }
                    }
                    .padding(EdgeInsets(top: 11, leading: 20, bottom: 11, trailing: 20))
                }

                if field != ItemsSortType.Field.allCases.last {
                    Divider()
                        .padding(.leading, 20)
                }
            }
        }
    }
}
