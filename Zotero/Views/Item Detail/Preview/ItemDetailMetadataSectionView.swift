//
//  ItemDetailMetadataSectionView.swift
//  Zotero
//
//  Created by Michal Rentka on 01/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemDetailMetadataSectionView: View {
    @EnvironmentObject private(set) var store: ItemDetailStore

    var body: some View {
        Section {
            ItemDetailMetadataView(title: "Item Type",
                                   value: self.store.state.data.localizedType)

            ForEach(self.store.state.data.creators) { creator in
                ItemDetailCreatorView(creator: creator)
            }

            ForEach(self.store.state.data.fields) { field in
                if !field.value.isEmpty {
                    ItemDetailMetadataView(title: field.name,
                                           value: field.value)
                }
            }

            self.store.state.data.abstract.flatMap {
                $0.isEmpty ? nil : ItemDetailAbstractView(abstract: $0)
            }
        }
    }
}

struct ItemDetailMetadataSectionView_Previews: PreviewProvider {
    static var previews: some View {
        List {
            ItemDetailMetadataSectionView()
        }
    }
}
