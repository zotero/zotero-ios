//
//  ItemDetailFieldView.swift
//  Zotero
//
//  Created by Michal Rentka on 27/08/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemDetailFieldView: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(self.title)
                .foregroundColor(.gray)
                .font(.headline)
                .fontWeight(.regular)
            Text(self.value)
        }
    }
}

#if DEBUG

struct ItemDetailFieldView_Previews: PreviewProvider {
    static var previews: some View {
        List {
            ItemDetailFieldView(title: "Title", value: "Some title")
            ItemDetailFieldView(title: "Item type", value: "Journal article")
            ItemDetailFieldView(title: "Pages", value: "23")
        }
    }
}

#endif
