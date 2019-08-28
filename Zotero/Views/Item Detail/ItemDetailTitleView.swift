//
//  ItemDetailTitleView.swift
//  Zotero
//
//  Created by Michal Rentka on 28/08/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemDetailTitleView: View {
    let title: String

    var body: some View {
        Text(self.title)
            .fontWeight(.light)
            .font(.title)
            .padding(.top)
    }
}

#if DEBUG

struct ItemDetailTitleView_Previews: PreviewProvider {
    static var previews: some View {
        List {
            ItemDetailTitleView(title: "Some title")
        }
    }
}

#endif
