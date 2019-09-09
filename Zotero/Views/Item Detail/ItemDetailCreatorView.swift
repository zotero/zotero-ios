//
//  ItemDetailCreatorView.swift
//  Zotero
//
//  Created by Michal Rentka on 05/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemDetailCreatorView: View {
    @Binding var creator: NewItemDetailStore.StoreState.Creator
    let editingEnabled: Bool

    var body: some View {
        HStack {
            ItemDetailFieldTitleView(title: self.creator.localizedType)
            if !self.editingEnabled {
                Text(self.creator.name)
            } else {
                if self.creator.namePresentation == .full {
                    TextField("Full name", text: self.$creator.fullName)
                } else if self.creator.namePresentation == .separate {
                    TextField("Last name", text: self.$creator.lastName)
                    Text(", ")
                    TextField("First name", text: self.$creator.firstName)
                }
                Spacer()
                // SWIFTUI BUG: - Button action in cell not called
                Button(action: {
                    self.creator.namePresentation.toggle()
                }) {
                    Text(self.creator.namePresentation == .full ? "Split name" : "Merge name").foregroundColor(.blue)
                }.onTapGesture {
                    self.creator.namePresentation.toggle()
                }
            }
        }
    }
}

struct ItemDetailCreatorView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ItemDetailCreatorView(creator: .constant(.init(firstName: "", lastName: "",
                                                           fullName: "First Last", type: "author",
                                                           localizedType: "Author")),
                                  editingEnabled: false)
            ItemDetailCreatorView(creator: .constant(.init(firstName: "First", lastName: "Last",
                                                           fullName: "", type: "author",
                                                           localizedType: "Author")),
                                  editingEnabled: false)
            ItemDetailCreatorView(creator: .constant(.init(firstName: "", lastName: "",
                                                           fullName: "First Last", type: "author",
                                                           localizedType: "Author")),
                                  editingEnabled: true)
            ItemDetailCreatorView(creator: .constant(.init(firstName: "First", lastName: "Last",
                                                           fullName: "", type: "author",
                                                           localizedType: "Author")),
                                  editingEnabled: true)
        }
    }
}
