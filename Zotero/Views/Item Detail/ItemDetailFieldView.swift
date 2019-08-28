//
//  ItemDetailFieldView.swift
//  Zotero
//
//  Created by Michal Rentka on 27/08/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemDetailFieldView: View {
    let field: NewItemDetailStore.StoreState.Field

    var body: some View {
        HStack {
            Text(self.field.name)
                .foregroundColor(.gray)
                .font(.headline)
                .fontWeight(.regular)
            Text(self.field.value)
        }
    }
}

#if DEBUG

struct ItemDetailFieldView_Previews: PreviewProvider {
    static var previews: some View {
        List {
            ItemDetailFieldView(field: .init(key: "", name: "Title",
                                             value: "Some journal article", isTitle: true,
                                             changed: false))
            ItemDetailFieldView(field: .init(key: "", name: "Item Type",
                                             value: "Journal article", isTitle: true,
                                             changed: false))
            ItemDetailFieldView(field: .init(key: "", name: "Pages",
                                             value: "23", isTitle: true,
                                             changed: false))
        }
    }
}

#endif
