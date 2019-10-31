//
//  TagPickerView.swift
//  Zotero
//
//  Created by Michal Rentka on 09/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct TagPickerView: View {
    @EnvironmentObject private(set) var store: TagPickerStore

    let saveAction: ([Tag]) -> Void
    let dismiss: () -> Void

    var body: some View {
        List(selection: self.$store.state.selectedTags) {
            ForEach(self.store.state.tags) { tag in
                TagView(color: .init(hex: tag.color), name: tag.name)
            }
        }
        .navigationBarItems(leading: self.leadingBarItems, trailing: self.trailingBarItems)
        .environment(\.editMode, .constant(.active))
        .onAppear(perform: self.store.load)
    }

    private var leadingBarItems: some View {
        return Button(action: self.dismiss) {
            return Text("Cancel")
        }
    }

    private var trailingBarItems: some View {
        return Button(action: {
            let tags = self.store.state.selectedTags.compactMap { id in
                self.store.state.tags.first(where: { $0.id == id })
            }.sorted(by: { $0.name < $1.name })
            self.saveAction(tags)
            self.dismiss()
        }) {
            return Text("Save")
        }
    }
}

struct TagPickerView_Previews: PreviewProvider {
    static var previews: some View {
        TagPickerView(saveAction: { _ in }, dismiss: {})
            .environmentObject(TagPickerStore(libraryId: .custom(.myLibrary),
                                              selectedTags: [],
                                              dbStorage: Controllers().dbStorage))
    }
}
