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

    let saveAction: (String) -> Void
    let closeAction: () -> Void

    var body: some View {
        List {
            ForEach(self.viewModel.state.objects) { object in
                Button(action: {
                    self.viewModel.process(action: .select(object.id))
                }) {
                    SinglePickerRow(text: object.name, isSelected: self.viewModel.state.selectedRow == object.id)
                }
            }
        }
        .navigationBarItems(leading: self.leadingItems, trailing: self.trailingItems)
    }

    private var leadingItems: some View {
        Button(action: self.closeAction) {
            Text("Cancel")
        }
    }

    private var trailingItems: some View {
        Button(action: {
            self.closeAction()
            self.saveAction(self.viewModel.state.selectedRow)
        }) {
            Text("Save")
        }
    }
}

struct SinglePickerView_Previews: PreviewProvider {
    static var previews: some View {
        SinglePickerView(saveAction: { _ in }, closeAction: {})
            .environmentObject(ViewModel(initialState: SinglePickerState(objects: [], selectedRow: ""),
                                         handler: SinglePickerActionHandler()))
    }
}
