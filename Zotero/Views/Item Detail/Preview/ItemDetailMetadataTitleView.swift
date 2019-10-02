//
//  ItemDetailMetadataTitleView.swift
//  Zotero
//
//  Created by Michal Rentka on 01/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemDetailMetadataTitleView: View {
    let title: String

    var body: some View {
        Text(self.title)
            .foregroundColor(.gray)
            .font(.headline)
            .fontWeight(.regular)
    }
}

struct ItemDetailMetadataTitleView_Previews: PreviewProvider {
    static var previews: some View {
        ItemDetailMetadataTitleView(title: "Some title")
    }
}
