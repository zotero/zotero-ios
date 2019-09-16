//
//  ItemsView.swift
//  Zotero
//
//  Created by Michal Rentka on 23/08/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

import RealmSwift

struct ItemsView: View {
    @ObservedObject private(set) var store: NewItemsStore

    var body: some View {
        List {
            self.store.state.sections.flatMap {
                ForEach($0, id: \.self) { section in
                    self.store.state.items(for: section).flatMap { ItemSectionView(results: $0) }
                }
            }
        }
    }
}

fileprivate struct ItemSectionView: View {
    let results: Results<RItem>

    var body: some View {
        Section {
            ForEach(self.results, id: \.key) { item in
                ItemRow(item: item)
            }
        }
    }
}

#if DEBUG

struct ItemsView_Previews: PreviewProvider {
    static var previews: some View {
        ItemsView(store: NewItemsStore(libraryId: .custom(.myLibrary),
                                       type: .all,
                                       metadataEditable: true,
                                       filesEditable: true,
                                       dbStorage: Controllers().dbStorage))
    }
}

#endif
