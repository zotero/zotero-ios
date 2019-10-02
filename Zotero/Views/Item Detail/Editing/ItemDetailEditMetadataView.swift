//
//  ItemDetailEditMetadataView.swift
//  Zotero
//
//  Created by Michal Rentka on 01/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemDetailEditMetadataView: View {
    let title: String
    @Binding var value: String

    var body: some View {
        HStack {
            ItemDetailMetadataTitleView(title: self.title)
            TextField(self.title, text: self.$value)
        }
    }
}

struct ItemDetailEditMetadataView_Previews: PreviewProvider {
    static var previews: some View {
        ItemDetailEditMetadataView(title: "Title",
                                   value: .constant("Value"))
    }
}
