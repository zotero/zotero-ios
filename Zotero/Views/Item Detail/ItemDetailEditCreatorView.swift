//
//  ItemDetailEditCreatorView.swift
//  Zotero
//
//  Created by Michal Rentka on 01/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemDetailEditCreatorView: View {
    @Binding var creator: ItemDetailStore.State.Creator

    var body: some View {
        HStack {
            ItemDetailMetadataTitleView(title: self.creator.localizedType)
            if self.creator.namePresentation == .full {
                TextField("Full name", text: self.$creator.fullName)
            } else if self.creator.namePresentation == .separate {
                TextField("Last name", text: self.$creator.lastName)
                Text(", ")
                TextField("First name", text: self.$creator.firstName)
            }
            Spacer()
            // SWIFTUI BUG: - Button action in cell not called in EditMode.active
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

struct ItemDetailEditCreatorView_Previews: PreviewProvider {
    static var previews: some View {
        ItemDetailEditCreatorView(creator: .constant(.init(type: "test", localizedType: "Test")))
    }
}
