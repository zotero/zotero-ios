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
    @Binding var value: String
    let editingEnabled: Bool

    var body: some View {
        HStack {
            ItemDetailFieldTitleView(title: self.title)
            if self.editingEnabled {
                TextField(self.title, text: self.$value)
            } else {
                Text(self.value)
            }
        }
    }
}

#if DEBUG

struct ItemDetailFieldView_Previews: PreviewProvider {
    static var previews: some View {
        List {
            ItemDetailFieldView(title: "Title", value: .constant("Some title"), editingEnabled: false)
            ItemDetailFieldView(title: "Item type", value: .constant("Journal article"), editingEnabled: false)
            ItemDetailFieldView(title: "Pages", value: .constant("23"), editingEnabled: false)
        }
    }
}

#endif
