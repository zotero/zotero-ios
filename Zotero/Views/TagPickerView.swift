//
//  TagPickerView.swift
//  Zotero
//
//  Created by Michal Rentka on 09/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct TagPickerView: View {
    @ObservedObject private(set) var store: TagPickerStore

    var body: some View {
        List(selection: self.$store.state.selectedTags) {
            ForEach(self.store.state.tags) { tag in
                TagView(color: tag.uiColor.flatMap(Color.init), name: tag.name)
            }
            // SWIFTUI BUG: - selection doesn't show up when deletion is not addeds
            .onDelete(perform: { _ in })
        }
        .environment(\.editMode, .constant(.active))
        .onAppear(perform: self.store.load)
    }
}

struct TagPickerView_Previews: PreviewProvider {
    static var previews: some View {
        TagPickerView(store: .init(libraryId: .custom(.myLibrary),
                                   selectedTags: [],
                                   dbStorage: Controllers().dbStorage))
    }
}
