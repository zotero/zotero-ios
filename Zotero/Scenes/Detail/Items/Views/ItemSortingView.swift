//
//  ItemSortingView.swift
//  Zotero
//
//  Created by Michal Rentka on 29.06.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemSortingView: View {
    @ObservedObject var viewModel: ViewModel<ItemsActionHandler>

    var showPickerAction: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Button {
                self.showPickerAction()
            } label: {
                HStack {
                    Text("\(L10n.Items.sortBy): \(self.viewModel.state.sortType.field.title)")
                        .foregroundColor(Color(UIColor.label))

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundColor(Color(UIColor.systemGray2))
                        .font(.body.weight(.semibold))
                        .imageScale(.small)
                }
            }
            .padding(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))

            Divider()

            Picker(L10n.Items.sortOrder, selection: self.viewModel.binding(get: \.sortType.ascending, action: { .setSortOrder($0) })) {
                Text("Ascending").tag(true)
                Text("Descending").tag(false)
            }
            .pickerStyle(.segmented)
            .padding(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
        }
        .padding(EdgeInsets(top: 20, leading: 0, bottom: 20, trailing: 0))
    }
}
