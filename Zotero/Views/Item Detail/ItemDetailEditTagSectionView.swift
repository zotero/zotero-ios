//
//  ItemDetailEditTagSectionView.swift
//  Zotero
//
//  Created by Michal Rentka on 01/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemDetailEditTagSectionView: View {
    @EnvironmentObject var store: ItemDetailStore

    var body: some View {
        Section {
            Section {
                ItemDetailSectionView(title: "Tags")
                ForEach(self.store.state.data.tags) { tag in
                    TagView(color: Color(hex: tag.color), name: tag.name)
                }
                .onDelete(perform: self.store.deleteTags)
                ItemDetailAddView(title: "Add tag", action: { self.store.state.showTagPicker = true })
            }
        }
    }
}

struct ItemDetailEditTagSectionView_Previews: PreviewProvider {
    static var previews: some View {
        ItemDetailEditTagSectionView()
    }
}
