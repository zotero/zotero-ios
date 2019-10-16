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

    var body: some View {
        VStack(spacing: 0) {
            List(selection: self.$store.state.selectedTags) {
                ForEach(self.store.state.tags) { tag in
                    TagView(color: .init(hex: tag.color), name: tag.name)
                }
            }

            Button(action: {
                let tags = self.store.state.selectedTags.compactMap { id in
                    self.store.state.tags.first(where: { $0.id == id })
                }.sorted(by: { $0.name < $1.name })
                self.saveAction(tags)
            }) {
                Text("Save")
                    .foregroundColor(.white)
                    .font(.callout)
                    .fontWeight(.bold)
            }
            .padding(.vertical)
            .frame(maxWidth: .infinity)
            .background(Color.blue)
        }
        .environment(\.editMode, .constant(.active))
        .onAppear(perform: self.store.load)
    }
}

struct TagPickerView_Previews: PreviewProvider {
    static var previews: some View {
        TagPickerView(saveAction: { _ in })
            .environmentObject(TagPickerStore(libraryId: .custom(.myLibrary),
                                              selectedTags: [],
                                              dbStorage: Controllers().dbStorage))
    }
}
