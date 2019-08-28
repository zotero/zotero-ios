//
//  ItemDetailSectionView.swift
//  Zotero
//
//  Created by Michal Rentka on 28/08/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemDetailSectionView: View {
    let title: String

    var body: some View {
        Text(self.title)
            .fontWeight(.light)
            .font(.headline)
    }
}

struct ItemDetailSectionView_Previews: PreviewProvider {
    static var previews: some View {
        ItemDetailSectionView(title: "Section")
    }
}
