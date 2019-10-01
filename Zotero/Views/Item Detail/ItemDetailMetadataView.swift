//
//  ItemDetailMetadataView.swift
//  Zotero
//
//  Created by Michal Rentka on 01/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemDetailMetadataView: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            ItemDetailMetadataTitleView(title: self.title)
            Text(self.value)
        }
    }
}

struct ItemDetailMetadataView_Previews: PreviewProvider {
    static var previews: some View {
        ItemDetailMetadataView(title: "Title", value: "Value")
    }
}
