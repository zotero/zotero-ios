//
//  ItemDetailEditMetadataSectionView.swift
//  Zotero
//
//  Created by Michal Rentka on 01/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemDetailEditMetadataSectionView: View {
    @EnvironmentObject var store: ItemDetailStore

    var body: some View {
        Section {
            ItemDetailMetadataView(title: "Item Type", value: self.store.state.data.localizedType)

            ForEach(self.store.state.data.creators.indices, id:\.self) { index in
                ItemDetailEditCreatorView(creator: self.$store.state.data.creators[index])
            }

            ForEach(self.store.state.data.fields.indices, id: \.self) { index in
                ItemDetailEditMetadataView(title: self.store.state.data.fields[index].name,
                                           value: self.$store.state.data.fields[index].value)
            }

            Binding(self.$store.state.data.abstract).flatMap {
                ItemDetailEditAbstractView(abstract: $0)
            }
        }
    }
}

struct ItemDetailEditMetadataSectionView_Previews: PreviewProvider {
    static var previews: some View {
        ItemDetailEditMetadataSectionView()
    }
}
