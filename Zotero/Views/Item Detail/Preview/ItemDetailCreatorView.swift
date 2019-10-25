//
//  ItemDetailCreatorView.swift
//  Zotero
//
//  Created by Michal Rentka on 05/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemDetailCreatorView: View {
    let creator: ItemDetailStore.State.Creator

    var body: some View {
        HStack {
            ItemDetailMetadataTitleView(title: self.creator.localizedType)
            Text(self.creator.name)
        }
    }
}

struct ItemDetailCreatorView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ItemDetailCreatorView(creator: .init(firstName: "", lastName: "",
                                                 fullName: "First Last", type: "author", primary: true,
                                                 localizedType: "Author"))
            ItemDetailCreatorView(creator: .init(firstName: "First", lastName: "Last",
                                                 fullName: "", type: "author", primary: true,
                                                 localizedType: "Author"))
            ItemDetailCreatorView(creator: .init(firstName: "", lastName: "",
                                                 fullName: "First Last", type: "author", primary: true,
                                                 localizedType: "Author"))
            ItemDetailCreatorView(creator: .init(firstName: "First", lastName: "Last",
                                                 fullName: "", type: "author", primary: true,
                                                 localizedType: "Author"))
        }
    }
}
