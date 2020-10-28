//
//  SinglePickerView.swift
//  Zotero
//
//  Created by Michal Rentka on 23/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct SinglePickerView: View {
    @EnvironmentObject private var viewModel: ViewModel<SinglePickerActionHandler>

    let requiresSaveButton: Bool
    let requiresCancelButton: Bool
    let saveAction: (String) -> Void
    let closeAction: () -> Void

    var body: some View {
        List {
            ForEach(self.viewModel.state.objects) { object in
                Button(action: {
                    self.viewModel.process(action: .select(object.id))
                    if !self.requiresSaveButton {
                        self.save()
                    }
                }) {
                    SinglePickerRow(text: object.name, isSelected: self.viewModel.state.selectedRow == object.id)
                }
            }
        }
        .navigationBarItems(leading: self.leadingItems, trailing: self.trailingItems)
    }

    private var leadingItems: some View {
        Group {
            if self.requiresCancelButton {
                Button(action: self.closeAction) {
                    Text(L10n.cancel)
                        .padding(.vertical, 10)
                        .padding(.trailing, 10)
                }
            }
        }
    }

    private var trailingItems: some View {
        Group {
            if self.requiresSaveButton {
                Button(action: {
                    self.save()
                }) {
                    Text(L10n.save)
                        .padding(.vertical, 10)
                        .padding(.leading, 10)
                }
            }
        }
    }

    private func save() {
        self.closeAction()
        self.saveAction(self.viewModel.state.selectedRow)
    }
}

struct SinglePickerView_Previews: PreviewProvider {
    static var previews: some View {
        SinglePickerView(requiresSaveButton: true,
                         requiresCancelButton: true,
                         saveAction: { _ in }, closeAction: {})
            .environmentObject(ViewModel(initialState: SinglePickerState(objects: [], selectedRow: ""),
                                         handler: SinglePickerActionHandler()))
    }
}
