//
//  ItemDetailTagSectionView.swift
//  Zotero
//
//  Created by Michal Rentka on 01/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemDetailTagSectionView: View {
    @EnvironmentObject private(set) var store: ItemDetailStore

    var body: some View {
        Section {
            ItemDetailSectionVView(title: "Tags")
            ForEach(self.store.state.data.tags) { tag in
                TagView(color: Color(hex: tag.color), name: tag.name)
            }
        }
    }
}

struct ItemDetailTagSectionView_Previews: PreviewProvider {
    static var previews: some View {
        ItemDetailTagSectionView()
    }
}
