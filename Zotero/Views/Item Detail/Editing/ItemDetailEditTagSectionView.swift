//
//  ItemDetailEditTagSectionView.swift
//  Zotero
//
//  Created by Michal Rentka on 01/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemDetailEditTagSectionView: View {
    @EnvironmentObject private(set) var store: ItemDetailStore

    var body: some View {
        Section {
            ItemDetailSectionVView(title: "Tags")
            ForEach(self.store.state.data.tags) { tag in
                TagView(color: Color(hex: tag.color), name: tag.name)
            }
            .onDelete(perform: self.store.deleteTags)
            ItemDetailAddView(title: "Add tag", action: {
                NotificationCenter.default.post(name: .presentTagPicker, object: (Set(self.store.state.data.tags.map({ $0.id })), self.store.state.libraryId, self.store.setTags))
            })
        }
    }
}

struct ItemDetailEditTagSectionView_Previews: PreviewProvider {
    static var previews: some View {
        ItemDetailEditTagSectionView()
    }
}
