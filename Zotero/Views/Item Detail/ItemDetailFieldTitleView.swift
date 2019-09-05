//
//  ItemDetailFieldTitleView.swift
//  Zotero
//
//  Created by Michal Rentka on 05/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemDetailFieldTitleView: View {
    let title: String

    var body: some View {
        Text(self.title)
            .foregroundColor(.gray)
            .font(.headline)
            .fontWeight(.regular)
    }
}

struct ItemDetailFieldTitleView_Previews: PreviewProvider {
    static var previews: some View {
        ItemDetailFieldTitleView(title: "Title")
    }
}
